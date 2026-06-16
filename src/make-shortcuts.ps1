# Cria/atualiza atalhos no Menu Iniciar e na Area de Trabalho apontando pro exe.
# A elevacao (UAC) vem do manifest do exe, entao o atalho ja pede admin.
$ErrorActionPreference = 'Stop'
$exe  = (Resolve-Path "$PSScriptRoot\..\bin\SefazThrottle.exe").Path
$work = Split-Path $exe
$name = "Limitador SEFAZ NFCe.lnk"
$ws = New-Object -ComObject WScript.Shell
$targets = @(
  (Join-Path ([Environment]::GetFolderPath('Programs')) $name),
  (Join-Path ([Environment]::GetFolderPath('Desktop'))  $name)
)
foreach ($lnkPath in $targets) {
  $lnk = $ws.CreateShortcut($lnkPath)
  $lnk.TargetPath = $exe
  $lnk.WorkingDirectory = $work
  $lnk.IconLocation = "$exe,0"
  $lnk.Description = "Limitador de internet p/ testes de contingencia NFCe"
  $lnk.WindowStyle = 1
  $lnk.Save()
  Write-Output "atalho: $lnkPath"
}
