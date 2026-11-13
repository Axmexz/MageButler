param([Parameter(Mandatory = $true)][string]$OutDir)

# Writes small uncompressed 32-bit TGA textures (power-of-two, straight alpha).
# All shapes are radially symmetric, so row order does not matter.

function Clamp01([double]$v) { if ($v -lt 0) { return 0.0 } elseif ($v -gt 1) { return 1.0 } else { return $v } }

function Write-Tga([string]$Path, [int]$Size, [scriptblock]$Pixel) {
    $bytes = New-Object byte[] (18 + $Size * $Size * 4)
    $bytes[2] = 2                      # uncompressed true-colour
    $bytes[12] = $Size -band 0xFF; $bytes[13] = ($Size -shr 8) -band 0xFF
    $bytes[14] = $Size -band 0xFF; $bytes[15] = ($Size -shr 8) -band 0xFF
    $bytes[16] = 32                    # bits per pixel
    $bytes[17] = 8                     # 8 alpha bits, bottom-left origin
    $c = ($Size - 1) / 2.0
    $i = 18
    for ($y = 0; $y -lt $Size; $y++) {
        for ($x = 0; $x -lt $Size; $x++) {
            $dx = $x - $c; $dy = $y - $c
            $d = [math]::Sqrt($dx * $dx + $dy * $dy)
            $p = & $Pixel $d          # returns r,g,b,a as 0..1
            $bytes[$i]     = [byte][math]::Round(255 * (Clamp01 $p[2]))
            $bytes[$i + 1] = [byte][math]::Round(255 * (Clamp01 $p[1]))
            $bytes[$i + 2] = [byte][math]::Round(255 * (Clamp01 $p[0]))
            $bytes[$i + 3] = [byte][math]::Round(255 * (Clamp01 $p[3]))
            $i += 4
        }
    }
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

function Mix([double[]]$a, [double[]]$b, [double]$t) {
    return @(($a[0] + ($b[0] - $a[0]) * $t), ($a[1] + ($b[1] - $a[1]) * $t), ($a[2] + ($b[2] - $a[2]) * $t))
}

New-Item -ItemType Directory -Force $OutDir | Out-Null

# Solid disc, anti-aliased edge. Used as a background and as a circular icon mask.
Write-Tga (Join-Path $OutDir "Circle.tga") 64 {
    param($d)
    return @(1.0, 1.0, 1.0, (Clamp01 (30.5 - $d + 0.5)))
}

# Border ring for round buttons.
Write-Tga (Join-Path $OutDir "Ring.tga") 128 {
    param($d)
    $a = (Clamp01 (62.0 - $d + 0.5)) * (Clamp01 ($d - 56.5 + 0.5))
    return @(1.0, 1.0, 1.0, $a)
}

# Hairline ring for the orbit guide behind the radial buttons.
Write-Tga (Join-Path $OutDir "RingThin.tga") 256 {
    param($d)
    $a = (Clamp01 (125.0 - $d + 0.5)) * (Clamp01 ($d - 123.0 + 0.5))
    return @(1.0, 1.0, 1.0, $a)
}

# Soft radial glow (additive).
Write-Tga (Join-Path $OutDir "Glow.tga") 128 {
    param($d)
    $t = Clamp01 (1.0 - $d / 63.5)
    return @(1.0, 1.0, 1.0, ($t * $t))
}

# Orb core: purple centre fading to midnight navy, as in the concept art.
$c0 = @(0.271, 0.231, 0.604); $c1 = @(0.094, 0.173, 0.388); $c2 = @(0.027, 0.086, 0.145)
Write-Tga (Join-Path $OutDir "Orb.tga") 128 {
    param($d)
    $t = Clamp01 ($d / 62.0)
    if ($t -lt 0.65) { $rgb = Mix $c0 $c1 ($t / 0.65) } else { $rgb = Mix $c1 $c2 (($t - 0.65) / 0.35) }
    return @($rgb[0], $rgb[1], $rgb[2], (Clamp01 (62.0 - $d + 0.5)))
}

Get-ChildItem $OutDir -Filter *.tga | ForEach-Object { "{0,-14} {1,8} bytes" -f $_.Name, $_.Length }
