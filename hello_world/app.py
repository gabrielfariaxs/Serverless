import base64
import json
import time

contador = 0


def lambda_handler(event, context):
    global contador
    contador += 1

    try:
        raw_body = event.get("body")
        if event.get("isBase64Encoded") and isinstance(raw_body, str):
            raw_body = base64.b64decode(raw_body).decode("utf-8")

        if isinstance(raw_body, str):
            body = json.loads(raw_body) if raw_body else {}
        elif isinstance(raw_body, dict):
            body = raw_body
        else:
            body = {}
    except Exception:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"erro": "JSON invalido no corpo da requisicao"}),
        }

    requisicao_id = body.get("requisicaoId")
    if not requisicao_id:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"erro": "Campo 'requisicaoId' e obrigatorio"}),
        }

    if body.get("demorar") is True:
        time.sleep(5)

    resposta = {
        "guia": f"G-{requisicao_id}",
        "hospital": body.get("hospital"),
        "bolsas": body.get("bolsas"),
        "invocacaoNesteAmbiente": contador,
    }

    return {
        "statusCode": 201,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(resposta),
    }
