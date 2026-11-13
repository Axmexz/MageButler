param(
    [int]$Port = 8765,
    [Parameter(Mandatory = $true)][string]$AddonDir,
    [Parameter(Mandatory = $true)][string]$HarnessDir
)

# Minimal static file server: /addon/* -> the addon folder, everything else -> the harness folder.
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving on http://localhost:$Port/"

$types = @{ ".html" = "text/html"; ".js" = "application/javascript"; ".lua" = "text/plain"; ".toc" = "text/plain" }

while ($listener.IsListening) {
    $context = $listener.GetContext()
    try {
        $path = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath)
        if ($path -like "/addon/*") {
            $root = $AddonDir
            $relative = $path.Substring(7)
        } else {
            $root = $HarnessDir
            if ($path -eq "/") { $path = "/index.html" }
            $relative = $path.TrimStart("/")
        }
        $file = [IO.Path]::GetFullPath((Join-Path $root $relative))
        $rootFull = [IO.Path]::GetFullPath($root)
        if ($file.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $file -PathType Leaf)) {
            $bytes = [IO.File]::ReadAllBytes($file)
            $ext = [IO.Path]::GetExtension($file).ToLower()
            $type = $types[$ext]
            if (-not $type) { $type = "application/octet-stream" }
            $context.Response.ContentType = "$type; charset=utf-8"
            $context.Response.Headers.Add("Cache-Control", "no-store")
            $context.Response.ContentLength64 = $bytes.Length
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $context.Response.StatusCode = 404
        }
    } catch {
        $context.Response.StatusCode = 500
    } finally {
        $context.Response.Close()
    }
}
