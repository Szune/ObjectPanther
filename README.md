# ObjectPanther
This script helps with querying hashtables (mainly JSON) in PowerShell.

It was created so I could perform some basic filtering on large json objects that come from an external API, where the documentation, while being fairly complete, could not explain how it was being used in practice.

There are bugs. However, as this is a personal project, I will only be fixing those that impede my own use of it.

## Known Issues
* Filters cannot be combined with and/or, they perform their filtering individually, one at a time.
I.e. if a value is filtered out by one filter, it cannot be retrieved by another filter
* Does not handle arrays as input

Workaround - wrap array in an object:
```powershell
@{Value=(Get-ChildItem -File | Select-Object -First 5)} |
  ConvertTo-Json -Depth 2 |
    Get-ObjectPath "Value/Name" -AsJson
# [
#   "ObjectPanther.ps1",
#   "README.md"
# ]
```

* Does not take hashtables directly

Workaround - convert object to JSON:
```powershell
$MyObject | ConvertTo-Json -Depth 2 | Get-ObjectPath "." -AsJson
```

## Examples

Parsing a json file, selecting the nested objects "Items" and then "Steps", filtering out all "Steps" objects where the property "Completed" is false:
```powershell
Get-ObjectPath "Items/Steps|Completed ne false|" -File 'pathToJsonFile.json' -AsJson # -JsonInput is the default
```

Parsing json from a pipeline:
```powershell
Get-Content 'pathToJsonFile.json' | Get-ObjectPath "Items/Steps|Completed ne false|" -AsJson # -JsonInput is the default
```

## Syntax/longer explanation
Selecting the current property, `.` :
```powershell
"Value/." # select Value, then select Value
# mostly useful to index on filtered items, e.g.
"Value|Name eq X|.[0]"
```

Selecting a property, `/` :
```powershell
"Value/Name" # select Value/Name
"./Value" # select current then Value
```

Indexing into an array, `[int]` :
```powershell
"Value[0]" # first item
"Value/.[0]" # alternative syntax (useful to get a subset of items that have been filtered, as [] requires a property)
```

Getting a range from an array, `[int:int]` :
```powershell
# There's also reverse ranges, but I haven't decided how I want them to work yet.
"Value[0:1]" # start at first item, take 1 item
"Value[1:3]" # start at second item, take 3 items
```

Filtering objects in an array, `|filterVariable op filterValue|`:
```powershell
"Value/Name|. ne ObjectPanther.ps1|" # select Value/Name and filter all values where Name is not "ObjectPanther.ps1"
"Value|Name ne ObjectPanther.ps1|" # select Value and filter all values where Name is not "ObjectPanther.ps1"
```

Filtering nested objects in an array, `|filterVariable/nestedVar op filterValue|`:
```powershell
"Value|Thing/Other. ne Y|" # select Value and filter all values where Thing->Other is not "Y"
```

Filtering and selecting objects in an array, `|filterVariable .op filterValue|`:
```powershell
"Value|Name .ne ObjectPanther.ps1|" # filter all values where Name is not "ObjectPanther.ps1"
```

Filter after a filter, `|filterVar1 op filterVal1||filterVar2 op filterVar2|`:
```powershell
"Value/Name|. ne ObjectPanther.ps1|" # select Value/Name and filter all values where Name is not "ObjectPanther.ps1"
"Value|Name ne ObjectPanther.ps1|" # select Value and filter all values where Name is not "ObjectPanther.ps1"
```

Implicitly selecting a property:
```powershell
"Value" # first part of the path (unless it's a filter)
"Value|Name eq Z|Name" # after a filter
```

## Filter operators

| Op       | Function               |
| -------- | ---------------------- |
| eq       | Equals                 |
| ne       | Not equals             |
| le       | Less than or equals    |
| lt       | Less than              |
| ge       | Greater than or equals |
| gt       | Greater than           |
| like     | Wildcard match         |
| notlike  | Not wildcard match     |

## Implicit filter values
The following filter values have to be surrounded with `"` to be interpreted literally.

I.e. `null` == `$null`, `"null"` == `null`

| Name  | Value  |
| ----- | ------ |
| null  | $null  |
| true  | $true  |
| false | $false |