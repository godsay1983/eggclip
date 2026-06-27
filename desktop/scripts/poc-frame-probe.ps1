param(
    [string]$HostName = "127.0.0.1",
    [Parameter(Mandatory = $true)]
    [int]$Port,
    [ValidateSet("all", "valid", "invalid-json", "empty-text", "text-too-large", "binary")]
    [string]$Case = "all"
)

$ErrorActionPreference = "Stop"

function Send-PocFrame {
    param(
        [byte[]]$Payload,
        [System.Net.WebSockets.WebSocketMessageType]$MessageType
    )

    $client = [System.Net.WebSockets.ClientWebSocket]::new()
    try {
        $uri = [Uri]::new("ws://${HostName}:${Port}")
        $client.ConnectAsync($uri, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
        $segment = [System.ArraySegment[byte]]::new($Payload)
        $client.SendAsync($segment, $MessageType, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
        Start-Sleep -Milliseconds 250
        if ($client.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $client.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "done",
                [System.Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()
        }
    } finally {
        $client.Dispose()
    }
}

function Send-TextProbe {
    param([string]$Payload)
    Send-PocFrame -Payload ([System.Text.Encoding]::UTF8.GetBytes($Payload)) -MessageType ([System.Net.WebSockets.WebSocketMessageType]::Text)
}

function Invoke-ProbeCase {
    param([string]$Name)

    switch ($Name) {
        "valid" {
            Send-TextProbe '{"kind":"clipboardText","text":"EggClip POC frame probe"}'
        }
        "invalid-json" {
            Send-TextProbe 'not json'
        }
        "empty-text" {
            Send-TextProbe '{"kind":"clipboardText","text":""}'
        }
        "text-too-large" {
            $oversized = "a" * (256 * 1024 + 1)
            Send-TextProbe (@{ kind = "clipboardText"; text = $oversized } | ConvertTo-Json -Compress)
        }
        "binary" {
            Send-PocFrame -Payload ([byte[]](0, 1, 2, 3)) -MessageType ([System.Net.WebSockets.WebSocketMessageType]::Binary)
        }
        default {
            throw "Unknown probe case: $Name"
        }
    }

    Write-Host "sent $Name"
}

if ($Case -eq "all") {
    @("valid", "invalid-json", "empty-text", "text-too-large", "binary") | ForEach-Object {
        Invoke-ProbeCase $_
    }
} else {
    Invoke-ProbeCase $Case
}
