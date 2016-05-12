#
# "THE BEER-WARE LICENSE" (Revision 42):
# <konstantin.vlasenko@gmail.com> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return.
#

# the timeout for the Remote server is 1 hour
$REMOTE_SERVER_READ_TIMEOUT = 60*60*1000

function Get-RemoteSlimSymbols($inputTable)
{
  $__pattern__ = '(?<id>scriptTable_\d+_\d+):\d{6}:callAndAssign:\d{6}:(?<name>\w+):\d{6}:'
  $inputTable | select-string $__pattern__ -allmatches | % {$_.matches} | % {@{id=$_.Groups[1].Value;name=$_.Groups[2].Value}}
}


function _serialize_slimsymbols($slimsymbols)
{
    $sb = new-object System.Text.StringBuilder
    $r = $sb.Append('[')
    $r = $sb.Append( $slimsymbols.Count.ToString("d6") )
    $r = $sb.Append(':')

    foreach($obj in $slimsymbols.GetEnumerator())
    {
        $val = if($obj.Value) { $obj.Value.ToString() } else { '' }
        $keyLen = $obj.Key.Length
        $valLen = $val.Length 
        
        $totalLen = 52 + 6 + $keyLen + 2 + 36 + 6 + $valLen + 4 + 1
        $r = $sb.Append($totalLen.ToString('d6')).Append(':'
        ).Append('[000006:000015:scriptTable_0_0:000013:callAndAssign:'  #52
        ).Append($keyLen.ToString('d6') #6
        ).Append(':').Append($obj.Key).Append(':' # $keyLen + 2 
        ).Append('000016:scriptTableActor:000004:eval:' #36
        ).Append( (($valLen + 2).ToString("d6"))  #6
        ).Append(":'").Append($val).Append("':").Append(']:'); # $valLen + 4 + 1
    }
    
    $sb.Append(']').ToString()
   
}

$script:SENT_SYMBOLS = @{}

function _send_slimsymbols($ps_computer, $ps_port, $slimsymbols)
{
    if($slimsymbols.Count -ne 0){
    
        $tr = _serialize_slimsymbols $slimsymbols
        #$tr | Out-Default 
    
        if( $script:SENT_SYMBOLS[ $ps_computer+$ps_port] -ne $tr)
        {
            $s2 = [text.encoding]::utf8.getbytes($tr).Length.ToString("d6") + ":" + $tr                     
            $s2 = [text.encoding]::utf8.getbytes($s2)
        
            "Connecting to $ps_computer $ps_port" | Out-Default

            $ps_sumbols_client = New-Object System.Net.Sockets.TcpClient($ps_computer, $ps_port)
            $remoteserver = $ps_sumbols_client.GetStream()
            $remoteserver.ReadTimeout = $REMOTE_SERVER_READ_TIMEOUT

            "Connected" | Out-Default

            $remoteserver.Write($s2, 0, $s2.Length)
            get_message($remoteserver)
        
            $script:SENT_SYMBOLS[ $ps_computer+$ps_port] = $tr
        }
    }
}

function script:process_table_remotely($ps_table, $ps_fitnesse){

    try {

      $originalslimbuffer = $ps_buf1 + $ps_buf2

      $result = new-Object 'system.collections.generic.dictionary[string,object]'

      foreach($t in $targets){ 

          $ps_computer, $ps_port1 = $t.split(':')

            if($ps_computer.StartsWith('$')){
                "Resolving symbol: $ps_computer " | Out-Default
                #$slimsymbols | Out-Default
                
                $ps_computer = $slimsymbols[$ps_computer.Substring(1)]
                $ps_computer, $ps_port2 = $ps_computer.split(':')
                "Resolved symbols: [$ps_computer], [$ps_port2]" | Out-Default
            }

          $ps_port = $ps_port2, $ps_port1, 35 | select -First 1

          Write-Verbose "Connecting to $ps_computer, $ps_port"
          
          _send_slimsymbols $ps_computer $ps_port $slimsymbols

         $ps_client = New-Object System.Net.Sockets.TcpClient($ps_computer, $ps_port)
         $remoteserver = $ps_client.GetStream()
         $remoteserver.ReadTimeout = $REMOTE_SERVER_READ_TIMEOUT
    
         $remoteserver.Write($originalslimbuffer, 0, $originalslimbuffer.Length)
         $result[$ps_computer] = get_message($remoteserver)
    
          #backward symbols sharing
         foreach($symbol in Get-RemoteSlimSymbols([text.encoding]::utf8.getstring($originalslimbuffer, 0, $originalslimbuffer.Length))) {
            $__pattern__ = "$($symbol.id):\d{6}:(?<value>.+?):\]"
            $slimsymbols[$symbol.name] = $result[$ps_computer] | select-string $__pattern__ | % {$_.matches} | % {$_.Groups[1].Value}
         }
      
         $remoteserver.Close()         
         $ps_client.Close() 

      }

      #if($result.Count -eq 1){

      #$res = $ps_buf1 + $ps_buf2
      #$ps_fitnesse.Write($res, 0, $res.Length)
      
      $ps_fitnesse.Write($ps_buf1, 0, $ps_buf1.Length)
      $ps_fitnesse.Write($ps_buf2, 0, $ps_buf2.Length)

      #}

    }
    catch [System.Exception] {
        $send = '[000002:' + (slimlen $ps_table[0][0]) + ':' + $ps_table[0][0] + ':' + (slimlen "$slimexception$($_.Exception.Message)") + ':' + "$slimexception$($_.Exception.Message)" + ':]'
        $send = (slimlen $send) + ":" + $send + ":"
        $send = [text.encoding]::utf8.getbytes((pack_results $send))
        $ps_fitnesse.Write($send, 0, $send.Length)
    }
}

function script:Test-TcpPort($ps_remotehost, $ps_port)
{
    $ErrorActionPreference = 'SilentlyContinue'
    $s = new-object Net.Sockets.TcpClient
    $s.Connect($ps_remotehost, $ps_port)
    if ($s.Connected) {
        $s.Close()
        return $true
    }
    return $false
}

function script:Wait-RemoteServer($ps_remotehost)
{
    while(!(Test-TcpPort $ps_remotehost 35)){sleep 10}
}
