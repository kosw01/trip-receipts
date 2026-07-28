# 사내망용으로 넣어놨다가 그냥 안지움 있어도 상관 X 
# Trip Receipts - static file server
#
# Run from an ADMIN PowerShell:
#   powershell -ExecutionPolicy Bypass -File ".\serve.ps1"
#
# Serves the folder this script sits in. No path editing needed.

$port = 8002

# ---------------------------------------------------------------
$root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
$rootFull = [System.IO.Path]::GetFullPath($root)

$mime = @{
  ".html" = "text/html; charset=utf-8"
  ".js"   = "application/javascript; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".png"  = "image/png"
  ".jpg"  = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".svg"  = "image/svg+xml"
  ".ico"  = "image/x-icon"
}

if (-not (Test-Path (Join-Path $rootFull "index.html"))) {
  Write-Host "WARNING: index.html not found in $rootFull" -ForegroundColor Yellow
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$port/")

try {
  $listener.Start()
} catch {
  Write-Host ""
  Write-Host "Failed to open port $port." -ForegroundColor Red
  Write-Host "  - Run PowerShell as Administrator" -ForegroundColor Red
  Write-Host "  - Or the port is already in use: Get-NetTCPConnection -LocalPort $port" -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "  Serving : $rootFull"
foreach ($ip in (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { $_.IPAddress -notlike "127.*" } | Select-Object -ExpandProperty IPAddress)) {
  Write-Host "  URL     : http://${ip}:$port/" -ForegroundColor Green
}
Write-Host "  Stop    : Ctrl + C"
Write-Host ""

while ($listener.IsListening) {
  try {
    $ctx = $listener.GetContext()
    $rel = [System.Uri]::UnescapeDataString($ctx.Request.Url.LocalPath).TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "index.html" }

    $file = [System.IO.Path]::GetFullPath((Join-Path $rootFull $rel))

    # block requests escaping the served folder
    if (-not $file.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
      $ctx.Response.StatusCode = 403
      $ctx.Response.Close()
      continue
    }

    if (Test-Path $file -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($file).ToLower()
      if ($mime.ContainsKey($ext)) {
        $ctx.Response.ContentType = $mime[$ext]
      } else {
        $ctx.Response.ContentType = "application/octet-stream"
      }
      # always serve the newest file - no browser caching
      $ctx.Response.Headers.Add("Cache-Control", "no-store, no-cache, must-revalidate")
      $ctx.Response.Headers.Add("Pragma", "no-cache")
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $ctx.Response.ContentLength64 = $bytes.Length
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
      Write-Host ("  200  " + $rel)
    } else {
      $ctx.Response.StatusCode = 404
      Write-Host ("  404  " + $rel) -ForegroundColor DarkYellow
    }
    $ctx.Response.Close()
  } catch {
    # ignore per-request errors and keep serving
  }
}
