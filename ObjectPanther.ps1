function Get-ObjectPath {
  [CmdletBinding()]
  param([Parameter(Position = 1)][string]$Path, [string]$File, [Parameter(ValueFromPipeline)][string]$SerializedText, [Switch]$JsonInput, [Switch]$AsJson)
  begin {
    $str = [System.Text.StringBuilder]::new()
  }
  process {
    $str = $str.AppendLine($SerializedText)
  }
  end {
    $str = if ([string]::IsNullOrWhiteSpace($File)) {
      $str.ToString()
    } else {
      Get-Content $File
    }
    $hashtableObject = if ($JsonInput) {
      $str | ConvertFrom-Json -AsHashTable
    } else {
      # TODO: handle different types of serialization and also just receiving a hashtable directly
      $str | ConvertFrom-Json -AsHashTable
    }

    class ObjectPanther {
      hidden [Hashtable]$hashObj
      hidden [string]$path
      hidden [int]$pos
      hidden $curObj
      hidden [System.Text.StringBuilder]$target # property, self '.', .[]

      ObjectPanther([string]$objPath, [Hashtable]$hashObject) {
          $this.pos = 0
          $this.path = $objPath
          $this.hashObj = $hashObject
          $this.target = [System.Text.StringBuilder]::new()
      }

      [pscustomobject]Recurse() {
        if($this.path -eq '.'){
          return $this.hashObj
        }
        $this.curObj = $this.hashObj
        return $this.RecurseExpr()
      }

      hidden [pscustomobject]RecurseExpr() {
        while($this.pos -lt $this.path.Length) {
          $this.RecurseTarget()
          if ($this.pos -ge $this.path.Length) {
            break
          }
          switch ($this.path[$this.pos]) {
            '[' { $this.pos++; $this.RecurseIndex() }
            '|' { $this.pos++; $this.RecurseFilter() }
            '/' { $this.pos++; $this.ExpandTarget() }
            '{' { $this.pos++; $this.SelectTarget() }
            default { throw "Unhandled char '$($this.path[$this.pos])' in RecurseExpr" }
          }
        }
        $this.ExpandTarget()
        return $this.curObj
      }

      hidden [string]GetTextUntilSpace() {
        $text = ""
        $filled = $false
        while($this.pos -lt $this.path.Length) {
          switch ($this.path[$this.pos]) {
            ' ' {
              $filled = $true
              break
            }
            default {
              $text += $this.path[$this.pos]
              break
            }
          }
          $this.pos++
          if($filled) {
            break
          }
        }

        return $text
      }

      hidden [array]GetSelectArgs() {
        $text = ""
        $filled = $false
        $allArgs = @()
        $curArg = [System.Text.StringBuilder]::new()
        while($this.pos -lt $this.path.Length) {
          switch ($this.path[$this.pos]) {
            ',' {
              if($curArg.Length -gt 0) {
                $allArgs += $curArg.ToString()
                $curArg = $curArg.Clear()
              }
              break
            }
            '}' {
              if($curArg.Length -gt 0) {
                $allArgs += $curArg.ToString()
                $curArg = $curArg.Clear()
              }
              $filled = $true
              break
            }
            ' ' {
              break
            }
            default {
              $curArg = $curArg.Append($this.path[$this.pos])
              break
            }
          }
          $this.pos++
          if($filled) {
            break
          }
        }

        return $allArgs
      }

      hidden [array] GetFilterParts() {
        $text = ""
        $filled = $false
        $parts = @()
        while($this.pos -lt $this.path.Length) {
          switch ($this.path[$this.pos]) {
            ' ' {
              $filled = $true
              if (-not [string]::IsNullOrWhiteSpace($text)) {
                $parts += $text
                $text = ""
              }
              break
            }
            '/' {
                $parts += $text
                $text = ""
            }
            default {
              $text += $this.path[$this.pos]
              break
            }
          }
          $this.pos++
          if($filled) {
            break
          }
        }

        if ($parts.Length -lt 1) {
          Write-Error "Missing first parameter in filter"
        }

        return $parts
      }

      hidden [ScriptBlock]GetCmpOp($op) {
        $cmp = switch($op) {
          'eq' {
            { param($a,$b) $a -eq $b }
          }
          'ne' {
            { param($a,$b) $a -ne $b }
          }
          'le' {
            { param($a,$b) $a -le $b }
          }
          'lt' {
            { param($a,$b) $a -lt $b }
          }
          'ge' {
            { param($a,$b) $a -ge $b }
          }
          'gt' {
            { param($a,$b) $a -gt $b }
          }
          'like' {
            { param($a,$b) $a -like $b }
          }
          'notlike' {
            { param($a,$b) $a -notlike $b }
          }
          # TODO: handle strings with escapes, plus regex in general
          # 'match' {
          #   { param($a,$b) $a -notlike $b }
          # }
          # 'notmatch' {
          #   { param($a,$b) $a -notlike $b }
          # }
          default {
            throw "Valid operators: 'eq', 'ne', 'le', 'lt', 'ge', 'gt', 'like', 'notlike'"
          }
        }
        return $cmp
      }

      hidden [void]RecurseFilter() {
        $this.ExpandTarget()
        $filterParts = $this.GetFilterParts()
        $op = $this.GetTextUntilSpace()
        $val = ""

        $valFull = $false
        $inStr = $false
        $wasString = $false
        while($this.pos -lt $this.path.Length) {
          switch ($this.path[$this.pos]) {
            '|' {
              if (-not $inStr) {
                $valFull = $true
              } else {
                $val += $this.path[$this.pos]
              }
              break
            }
            '"' {
              $wasString = $true
              $inStr = -not $inStr # very basic strings, no escaping or anything
            }
            default {
              $val += $this.path[$this.pos]
              break
            }
          }
          $this.pos++
          if($valFull) {
            break
          }
        }

        # get a compare function from the op
        $expand = $op.StartsWith('.')
        $compareFunc = $this.GetCmpOp($op.TrimStart('.'))

        if ($val -eq 'null' -and -not $wasString) {
          # turn null into $null unless it's in a string
          $val = $null
        } elseif ($val -eq 'true' -and -not $wasString) {
          # turn true into $true unless it's in a string
          $val = $true
        } elseif ($val -eq 'false' -and -not $wasString) {
          # turn false into $false unless it's in a string
          $val = $false
        }

        # match and optionally expand
        if($expand) {
          $filterParts |
            ForEach-Object {
              if($_ -ne '.') {
                $this.curObj = $this.curObj | Select-Object -ExpandProperty $_
              }
            }
          $this.curObj = $this.curObj |
            Where-Object {
              Invoke-Command -ArgumentList $_,$val -ScriptBlock $compareFunc
            }
        } else {
          $this.curObj = $this.curObj |
            Where-Object {
              $whereVar = $_
              $cmpVal = $filterParts |
                ForEach-Object {} {
                  $whereVar = if($_ -eq '.') {
                    $whereVar
                  } else {
                    $whereVar | Select-Object -ExpandProperty $_
                  }
                } { $whereVar }

              Invoke-Command -ArgumentList $cmpVal,$val -ScriptBlock $compareFunc
            }
        }
      }

      hidden [void]RecurseIndex() {
        $this.ExpandTarget()
        $index = ""
        $range = ""
        while($this.pos -lt $this.path.Length) {
          switch ($this.path[$this.pos]) {
            { $_ -ge '0' -and $_ -lt '9' } {
              $index += $_
              if ($range -eq "skip") {
                $range = "both"
              }
              break
            }
            '-' {
              $index += $_
              if ($range -eq "skip") {
                $range = "both"
              }
              break
            }
            ':' {
              if($index -eq "") {
                $range = "take"
              } else {
                $range = "skip"
              }
              $index += ':'
              break
            }
            ']' {
              # TODO: should be possible to optimize this part
              switch ($range) {
                'take' {
                  $amount = [int]($index -split ':')[1]
                  if ($amount -lt 0) {
                    $this.curObj = $this.curObj | Select-Object -Last (-$amount) | Sort-Object -Descending {(++$script:i)}
                  } else {
                    $this.curObj = $this.curObj | Select-Object -First $amount
                  }
                  break
                }
                'skip' {
                  $amount = [int]($index -split ':')[0]
                  if ($amount -lt 0) {
                    $this.curObj = $this.curObj | Select-Object -SkipLast (-$amount) | Sort-Object -Descending {(++$script:i)}
                  } else {
                    $this.curObj = $this.curObj | Select-Object -Skip $amount
                  }
                }
                'both' {
                  $both = ($index -split ':')
                  $first = [int]$both[0]
                  $last = [int]$both[1]
                  # TODO: make a reverse-object function from:
                  # | Sort-Object -Descending {(++$script:i)}

                  if($first -lt 0 -and $last -lt 0) {
                      $this.curObj = $this.curObj | Select-Object -SkipLast (-$first) | Select-Object -Last (-$last) | Sort-Object -Descending {(++$script:i)}
                  } else {
                    if($first -lt 0) {
                      $this.curObj = $this.curObj | Select-Object -SkipLast (-$first) | Sort-Object -Descending {(++$script:i)}
                    } else {
                      $this.curObj = $this.curObj | Select-Object -Skip $first
                    }

                    if ($last -lt 0) {
                      $this.curObj = $this.curObj | Select-Object -Last (-$last)
                    } else {
                      $this.curObj = $this.curObj | Select-Object -First $last
                    }
                  }
                }
                default { 
                  $this.curObj = $this.curObj[[int]$index]
                  break
                }
              }
              $this.pos++
              return
            }
            default { throw "Unhandled char '$_' in RecurseIndex" }
          }
          $this.pos++
        }
      }

      hidden [void]SelectTarget() {
        $this.ExpandTarget()
        $selecting = $this.GetSelectArgs()
        $this.curObj = $this.curObj | Select-Object $selecting
      }

      hidden [void]ExpandTarget() {
        $str = $this.target.ToString()
        $this.target.Clear()
        if ([string]::IsNullOrWhiteSpace($str)) {
          return
        }
        switch ($str) {
          '.' {
            break
          }
          default {
            if($this.curObj -is [array]) {
              $this.curObj = $this.curObj | Select-Object -ExpandProperty $str
            } else {
              $this.curObj = $this.curObj[$str]
            }
          }
        }
      }

      hidden [void]RecurseTarget() {
        while($this.pos -lt $this.path.Length) {
          switch ($this.path[$this.pos]) {
            { $_ -in @('[', '/', ']', '|', '{', '}') } {
              return
            }
            default {
              $this.target.Append($this.path[$this.pos])
            }
          }
          $this.pos++
        }
      }

    }

    $panther = [ObjectPanther]::new($Path,$hashtableObject)
    $result = $panther.Recurse()
    if ($AsJson) {
      $result | ConvertTo-Json -Depth 100
    } else {
      $result
    }
  }
}
