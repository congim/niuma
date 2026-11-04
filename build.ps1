# 编译 牛马脱敏器.exe（只需要 Windows 自带的 .NET Framework 4.x，无需安装任何东西）
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$fw = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319"
if (-not (Test-Path "$fw\csc.exe")) { $fw = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319" }
$wpf = "$fw\WPF"
$out = Join-Path $root '牛马脱敏器.exe'

$refs = @(
  "$wpf\PresentationFramework.dll", "$wpf\PresentationCore.dll", "$wpf\WindowsBase.dll",
  "$fw\System.Xaml.dll", "$fw\System.dll", "$fw\System.Core.dll",
  "$fw\System.Drawing.dll", "$fw\System.Windows.Forms.dll"
) | ForEach-Object { "/r:$_" }

$srcs = Get-ChildItem (Join-Path $root 'src') -Filter *.cs | ForEach-Object { $_.FullName }

& "$fw\csc.exe" /nologo /target:winexe /optimize+ /codepage:65001 /platform:anycpu `
  "/out:$out" "/win32icon:$root\src\app.ico" "/win32manifest:$root\src\app.manifest" `
  "/resource:$root\beij.png,NiuMa.beij.png" "/resource:$root\src\app.ico,NiuMa.app.ico" `
  @refs @srcs
if ($LASTEXITCODE -ne 0) { throw "编译失败" }
Write-Host "已生成 $out"
