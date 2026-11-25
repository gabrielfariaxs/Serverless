$env:Path = "C:\Program Files\Amazon\AWSSAMCLI\bin;C:\Users\Estagiario_Gabriel\AppData\Local\Programs\Python\Python312;C:\Users\Estagiario_Gabriel\AppData\Local\Programs\Python\Python312\Scripts;" + $env:Path
$env:SAM_CLI_TELEMETRY = "0"

Write-Host "========================================="
Write-Host "PARTE 1: sam local start-api (DEFAULT / SEM WARM CONTAINERS)"
Write-Host "========================================="

$job = Start-Process -FilePath "sam.cmd" -ArgumentList "local start-api --port 3000" -PassThru
Start-Sleep -Seconds 8

for ($i = 1; $i -le 3; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $resp = curl.exe -s -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" --data-binary "@events/body.json"
    $sw.Stop()
    Write-Host "Requisicao $i [$($sw.ElapsedMilliseconds) ms]: $resp"
}

taskkill /PID $job.Id /T /F | Out-Null
Start-Sleep -Seconds 3

Write-Host "`n========================================="
Write-Host "PARTE 2: sam local start-api --warm-containers LAZY"
Write-Host "========================================="

$job2 = Start-Process -FilePath "sam.cmd" -ArgumentList "local start-api --port 3000 --warm-containers LAZY" -PassThru
Start-Sleep -Seconds 8

for ($i = 1; $i -le 3; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $resp = curl.exe -s -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" --data-binary "@events/body.json"
    $sw.Stop()
    Write-Host "Requisicao $i [$($sw.ElapsedMilliseconds) ms]: $resp"
}

taskkill /PID $job2.Id /T /F | Out-Null

