# Atividade Prática de Serverless: Guia de Transporte com AWS SAM Local

Este repositório contém a atividade prática de computação Serverless utilizando **AWS SAM CLI**, **Docker** e **Python 3.12**, com o objetivo de analisar e evidenciar na prática os conceitos de **Cold Start**, **ausência de estado garantido (stateless)** e **Timeout**.

---

## 1. Caminho Escolhido

**Caminho Escolhido: Opção A (Execução 100% Local com AWS SAM CLI e Docker Engine)**

- **Justificativa:** Permite simular de forma fiel o comportamento da nuvem AWS (API Gateway Proxy + AWS Lambda runtime Python 3.12) diretamente na máquina local, dispensando custos de nuvem e permitindo inspeção precisa de tempos de inicialização de containers, ciclo de vida do ambiente de execução e timeouts.

---

## 2. Como Rodar o Projeto

### Pré-requisitos
- **Docker Desktop**: Em execução (com suporte a containers Linux/WSL2).
- **Python**: Versão 3.12 instalada.
- **AWS SAM CLI**: Versão 1.100+ instalada (`sam --version`).

### Passo 1: Clonar / Acessar a pasta do projeto
```bash
cd c:\Users\Estagiario_Gabriel\Serverless
```

### Passo 2: Construir a aplicação (Build)
O comando a seguir compila o template e prepara o pacote da Lambda dentro de `.aws-sam/build`:
```bash
sam build
```

### Passo 3: Invocação Direta via Evento (Invocação Pontual)
Para testar a emissão de uma guia com o payload contido em `events/pedido.json`:
```bash
sam local invoke -e events/pedido.json
```

Para cronometrar a invocação no PowerShell:
```powershell
Measure-Command { sam local invoke -e events/pedido.json }
```

### Passo 4: Executar a API Gateway Localmente
#### Modo Padrão (Containers Efêmeros / Sem Warm Containers):
```bash
sam local start-api --port 3000
```
Em outro terminal, envie as requisições:
```bash
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" --data-binary "@events/body.json"
```

#### Modo com Containers Quentes (Warm Containers LAZY):
```bash
sam local start-api --port 3000 --warm-containers LAZY
```
Envie requisições repetidas para observar o incremento do contador de memória:
```bash
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" --data-binary "@events/body.json"
```

### Passo 5: Teste de Timeout
1. No `template.yaml`, mantenha `Globals -> Function -> Timeout: 3`.
2. Execute a chamada com o evento que aciona atraso de 5 segundos:
   ```bash
   sam local invoke -e events/pedido_demorado.json
   ```
   *Resultado esperado:* Erro de timeout aos 3 segundos (`timed out after 3 seconds`).
3. Altere o `Timeout` no `template.yaml` para `10`, execute `sam build` e repita o comando:
   *Resultado esperado:* Sucesso com HTTP 201 e duração aproximada de 5.070 ms.

---

## 3. Estrutura de Arquivos

```text
├── template.yaml                  # Definição dos recursos SAM (Lambda, API Gateway, Globals)
├── samconfig.toml                 # Configurações do SAM CLI
├── hello_world/
│   ├── app.py                     # Handler Python 3.12 com controle de contador e timeout
│   └── requirements.txt           # Dependências Python
├── events/
│   ├── pedido.json                # Evento API Gateway Proxy gerado via SAM CLI
│   ├── pedido_demorado.json       # Evento com payload {"demorar": true} para teste de timeout
│   └── body.json                  # Corpo bruto da requisição para testes via curl
├── evidencias/
│   ├── 01-versao-ferramentas.txt  # Saída com as versões do Docker, SAM e Python
│   ├── 02-sam-build-e-invoke.txt  # Evidência das duas invocações e tempos (Cold Start)
│   ├── 03-start-api-sem-warm-containers.txt  # 3 requisições sem warm containers
│   ├── 04-start-api-com-warm-containers-lazy.txt # 3 requisições com warm containers LAZY
│   └── 05-timeout-erro-e-sucesso.txt         # Evidência de timeout (3s) e correção (10s)
└── README.md
```

---

## 4. Perguntas da Atividade (Respostas do Estudante)

### Pergunta 1: O que é Cold Start e como ele foi observado neste experimento?
O Cold Start é a latência adicional que ocorre na primeira invocação de uma função serverless (ou após um período de inatividade / escalonamento horizontal). Nesse momento, o provedor de computação precisa provisionar os recursos sob demanda: alocar o container/microVM, carregar o pacote da aplicação, inicializar o runtime e executar as instruções estáticas fora do handler (como importação de bibliotecas e declaração de variáveis globais). Nas chamadas seguintes direcionadas a um ambiente já ativo (*warm start*), essas etapas são ignoradas, executando o código quase instantaneamente sobre a memória já carregada.

Neste experimento prático, o Cold Start foi observado de forma quantitativa e qualitativa em dois cenários:

1. **Na invocação via CLI (`sam local invoke`):**
   - **1ª Invocação (Cold Start com download de imagem):** O SAM CLI levou **39.714 ms (~39,7 s)** para baixar a imagem Docker de emulação (`public.ecr.aws/lambda/python:3.12-rapid-x86_64`), criar a estrutura do container e disparar o runtime.
   - **2ª Invocação:** Com as camadas da imagem em cache no Docker local, o tempo total despencou para **7.083 ms (~7,1 s)**.
   - Nos relatórios de execução do Lambda (`REPORT ... Init Duration: 0.08 ms Duration: 71.60 ms`), o campo `Init Duration` identificou com precisão a fase de bootstrap do interpretador Python antes da entrada no `lambda_handler`.

2. **Na API HTTP (`sam local start-api --warm-containers LAZY`):**
   - **1ª Requisição:** Levou **3.395 ms**, pois o container teve que ser instanciado sob demanda no momento em que a rota `/guias` recebeu tráfego.
   - **2ª e 3ª Requisições:** Como o container foi mantido aquecido (*warm*) na memória, os tempos caíram para **1.086 ms** e **1.092 ms**, comprovando uma **redução de ~68% na latência** percebida pelo cliente entre a inicialização a frio e as execuções quentes subsequentes.


---

### Pergunta 2: Por que arquiteturas Serverless não garantem persistência de estado em variáveis globais/memória?
Em arquiteturas Serverless (como o AWS Lambda), as funções são concebidas sob o princípio fundamental do Stateless (ausência de estado persistido no nó de computação). Isso ocorre pelas seguintes razões arquiteturais:

1. **Ciclo de Vida Efêmero e Gerenciado:** Os ambientes de execução (microVMs ou containers) são criados, mantidos e destruídos de forma totalmente autônoma pelo provedor de nuvem. Quando o tráfego cessa ou após um período de ociosidade (*scale-to-zero*), o container é encerrado e toda a memória RAM associada ao processo é desalocada.
2. **Escalabilidade Horizontal Elástica:** Em picos de demanda ou chamadas concorrentes, o provedor instancia múltiplas réplicas paralelas da função. Cada container possui seu próprio espaço de endereçamento de memória isolado; portanto, uma variável global (como o `contador`) atualizada na réplica A nunca será visível para a réplica B.
3. **Rotatividade de Infraestrutura:** Mesmo durante fluxos contínuos de requisições, o provedor pode reciclar os containers a qualquer momento para aplicação de patches de segurança, balanceamento de carga ou manutenção física dos servidores.

**Conclusão prática:** Variáveis globais em Serverless servem apenas como **cache transitório** de curta duração (como reaproveitamento de conexões de banco ou carregamento de SDKs). Qualquer estado que precise sobreviver entre requisições ou ser compartilhado entre instâncias deve ser delegado a camadas de persistência externa desacopladas, tais como **Amazon DynamoDB**, **Redis/ElastiCache**, **Amazon S3** ou bancos de dados relacionais (**RDS**).


---

### Pergunta 3: Qual foi a diferença prática observada no comportamento de `invocacaoNesteAmbiente` entre o modo padrão e o modo com `--warm-containers LAZY`?
A diferença prática reside no ciclo de vida dos containers Docker gerenciados pelo SAM CLI:

1. **Modo Padrão (`sam local start-api`):**
   - A cada requisição HTTP enviada para `/guias`, o SAM criou um container novo, executou o código e finalizou o container imediatamente após a resposta.
   - Como o processo Python era reiniciado do zero em cada chamada, a variável global `contador` sempre voltava para `0`.
   - **Resultado:** Todas as 3 requisições retornaram `"invocacaoNesteAmbiente": 1`, com tempos de resposta entre 1.741 ms e 3.685 ms.

2. **Modo com `--warm-containers LAZY`:**
   - O container foi instanciado sob demanda na 1ª requisição e **mantido ativo em memória RAM** para processar as requisições seguintes.
   - Como o mesmo processo Python permaneceu em execução, o estado da memória global foi preservado.
   - **Resultado:** As 3 requisições retornaram sequencialmente `"invocacaoNesteAmbiente": 1`, `"invocacaoNesteAmbiente": 2` e `"invocacaoNesteAmbiente": 3`.
   - **Ganho de desempenho:** A latência caiu de **3.395 ms** (1ª requisição - Cold Start) para **1.086 ms** e **1.092 ms** nas requisições 2 e 3 (Warm Start), representando uma **redução de aproximadamente 68% no tempo de resposta**.

---

### Pergunta 4: O que acontece quando o tempo de execução da função ultrapassa o limite de Timeout configurado na AWS Lambda e como isso afeta a arquitetura?
Quando a função excede o tempo limite configurado no template (`Timeout: 3` segundos):

1. **Aborto Compulsorio:** O runtime da Lambda interrompe forçadamente o processamento. O container é congelado ou destruído sem emitir a resposta HTTP esperada pelo `lambda_handler`.
2. **Impacto no API Gateway e no Cliente:** O cliente recebe uma falha de conexão (HTTP 502 Bad Gateway ou 504 Gateway Timeout), e os logs do SAM/CloudWatch registram explicitamente o erro:
   `Function 'HelloWorldFunction' timed out after 3 seconds` e `No response from invoke container`.
3. **Inconsistência de Dados e Retentativas:** Operações parcialmente executadas (como gravações parciais em banco ou transações externas) são interrompidas abruptamente. Em fluxos assíncronos (como mensagens via SQS), um timeout faz a mensagem retornar à fila para nova tentativa, exigindo que o código seja rigorosamente **idempotente** para evitar efeitos colaterais duplicados.
4. **Validação no Experimento:** Com o payload `{"demorar": true}` acionando um `time.sleep(5)`, a execução falhou sistematicamente sob `Timeout: 3`. Ao elevarmos o parâmetro para `Timeout: 10` e recompilarmos (`sam build`), a função executou os 5 segundos de espera com folga e concluiu com sucesso em **5.072 ms** (HTTP 201).

---

### Pergunta 5: Em quais cenários do mundo real um desenvolvedor deve adotar estratégias de warm up / provisioned concurrency versus arquiteturas puramente assíncronas/desacopladas?
A escolha entre essas abordagens depende da natureza da interação do usuário e da duração da tarefa:

- **Provisioned Concurrency / Warm Up:**
  - **Quando usar:** Em APIs síncronas de missão crítica voltadas diretamente ao usuário final, onde SLAs de latência são estritos (sub-segundo) e a experiência de uso seria prejudicada por um Cold Start de 2 a 5 segundos.
  - **Exemplos reais:** Telas de login e autenticação, processamento de pagamentos/checkout de e-commerce, buscas em catálogo de produtos e sistemas de triagem de emergência hospitalar.
  - **Custo x Benefício:** Possui custo financeiro adicional (pois instâncias ficam reservadas e pagas continuamente), mas garante resposta instantânea sem cold start.

- **Arquiteturas Assíncronas e Desacopladas (SQS, SNS, EventBridge, Step Functions):**
  - **Quando usar:** Em processos que naturalmente demandam tempo (operações de I/O pesadas, processamento em lote, conversão de arquivos, emissão massiva de guias ou integração com sistemas legados lentos).
  - **Exemplos reais:** Processamento de lotes de doações de sangue, geração de relatórios analíticos, reconciliação financeira noturna e envio em massa de notificações.
  - **Padrão arquitetural:** A API síncrona valida a entrada e responde de imediato com `202 Accepted` contendo um `protocoloId`. A função envia a mensagem para uma fila e o trabalho pesado roda em segundo plano. Isso elimina o risco de timeout de gateways (limite de 29s no API Gateway AWS) e torna a solução imune ao impacto de Cold Starts.

---

## 5. Uso de IA

Nesta atividade prática, as ferramentas de Inteligência Artificial atuaram como um **copiloto técnico e analítico** em todo o ciclo de desenvolvimento e verificação experimental:

1. **Diagnóstico e Configuração do Ambiente Local:**
   Identificação das versões necessárias e auxílio na instalação e configuração do interpretador Python 3.12, da AWS SAM CLI e na inicialização correta do daemon do Docker Desktop no Windows.
2. **Infraestrutura como Código (IaC):**
   Ajuste das definições declarativas em `template.yaml` (atualização de rotas `/guias`, métodos HTTP `POST` e escopos globais de `Timeout`) e parametrização do `samconfig.toml`.
3. **Resiliência no Código da Aplicação:**
   Elaboração do handler Python em `hello_world/app.py`, garantindo o correto tratamento de eventos codificados em Base64 pelo proxy do API Gateway e a manipulação robusta de exceções de payload.
4. **Automação e Interpretação dos Experimentos:**
   Criação de scripts para cronometragem precisa das invocações, permitindo comparar numericamente as latências de Cold Start versus Warm Start, registrar a persistência da variável global entre containers e analisar a causa-raiz do estouro de Timeout.


