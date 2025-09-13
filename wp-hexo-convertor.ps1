param (
    [string]$sourceDirectory
)

if ([string]::IsNullOrEmpty($sourceDirectory)) {
    $configPath = "wp-hexo-convertor.json"
    if (Test-Path $configPath -PathType Leaf) {
        $config = Get-Content -Path $configPath | ConvertFrom-Json
        $sourceDirectory = $config.SourceDirectory
    }
}

if ([string]::IsNullOrEmpty($sourceDirectory)) {
    Write-Output "Usage: .\wp-hexo-convertor.ps1 sourceDirectory"
    Write-Output "`r`nYou can specify source directory in wp-hexo-convertor.json, example:"
    Write-Output "{"
    Write-Output "    ""SourceDirectory"": ""c:\\my_wp_blog_path"""
    Write-Output "}"
    exit
}

Write-Output "source directory: $sourceDirectory"

$categoryPathTitles = "`n"
$postCategoryTitles = "`n"

$sourceCatRegEx = '^(cat=[1-9][0-9]*)(&.*)?$'
Get-ChildItem -Path $sourceDirectory | Where-Object {$_.Name -match $sourceCatRegEx } | ForEach-Object {
    $sourceCatPath = $_.Name
    $html = "$($_.FullName)\index.html"    
    $htmlContent = Get-Content $html
    Select-String -InputObject $sourceCatPath -Pattern $sourceCatRegEx | ForEach-Object { 
        $category = $_.Matches.Groups[1].Value
        Write-Output "source category: $sourceCatPath"
        $title = ""
        Select-String -InputObject $htmlContent -Pattern "<a[^>]* aria-current=""page""[^>]*>([^<]+)<\/a>" | ForEach-Object {
            $title = $_.Matches.Groups[1].Value
            Write-Output "category title: $title"
        }
        if ($title -ne "") {
            $categoryPathTitles += "$sourceCatPath/$title`n"
            Select-String -InputObject $htmlContent -Pattern "<a[^>]* href=""\/blog\/(p=[1-9][0-9]*)\/""[^>]*>([^<]+)<\/a>" -AllMatches | ForEach-Object {
                foreach($m in $_.Matches) {
                    $postPath = $m.Groups[1].Value
                    $postCategoryTitle = "$postPath/$category/$title"
                    $postCategoryTitles += "$postCategoryTitle`n"
                    Write-Output "category post path: $postPath"
                }
            }
        }
        else {
            Write-Output "category title not found"
        }
    }
}

$tagPathText = "`n"

Get-ChildItem -Path $sourceDirectory | Where-Object {$_.Name -match '^p=[1-9][0-9]*$' } | ForEach-Object {
    $sourcePostPath = $_.Name
    Write-Output "source post: $sourcePostPath"
    $tempFolder = "temp"
    $tmpMd = "$tempFolder\$sourcePostPath.md.tmp"
    $html = "$($_.FullName)\index.html"
    $htmlContent = Get-Content $html
    $fixedHtmlContent = ""
    $tags = ""
    $tagRegex = "(<a[^>]*) rel=""tag""([^>]*>)([^<]*)(<\/a>)"
    $categories = ""
    Select-String -InputObject $postCategoryTitles -Pattern "\n$sourcePostPath\/([^\/]*)\/([^\n]*)" -AllMatches | ForEach-Object {
        foreach($m in $_.Matches) {
            $category = $m.Groups[1].Value
            $title = $m.Groups[2].Value
            Write-Output "post category: $category, title: $title"
            $categories += "`r`n  - - ""$title"""
        }
    }    
    $hr = $false
    foreach ($line in $htmlContent) {
        if ($line -match "<hr\/?>") {
            $hr = $true
        }
        if (!$hr) {
            Select-String -InputObject $line -Pattern $tagRegex -AllMatches | ForEach-Object {
                foreach($m in $_.Matches) {
                    $tagText = $m.Groups[3].Value
                    Write-Output "post tag: $tagText"
                    $tags += "`r`n  - ""$tagText"""
                    Select-String -InputObject $m.Value -Pattern 'href="\/blog\/(tag=[^"\/]*)/"' | ForEach-Object {
                        $tagPath = $_.Matches.Groups[1].Value
                        Write-Output "post tag path: $tagPath"
                        $tagPathText += "$tagPath/$tagText`n"
                    }
                }
            }
        }
        $line = $line -replace "(<a[^>]*) class=""[^""]*""", '$1'
        $line = $line -replace "(<a[^>]*) onclick=""[^""]*""", '$1'
        $line = $line -replace "(<a[^>]*) rel=""[^""]*""", '$1'
        $line = $line -replace "(<a[^>]*) aria-label=""[^""]*""", '$1'
        $line = $line -replace "(<a[^>]*) target=""[^""]*""", '$1'
        $line = $line -replace "(<img[^>]*) class=""[^""]*""", '$1'
        $line = $line -replace "(<img[^>]*) width=""[^""]*""", '$1'
        $line = $line -replace "(<img[^>]*) height=""[^""]*""", '$1'
        $line = $line -replace "(<img[^>]*) src=""\/blog(\/wp-content\/[^""]*)""", '$1 src="$2"'
        $line = $line -replace "(<h[1-9][^>]*) style=""[^""]*""", '$1'
        $line = $line -replace "<\/?small>", ''
        $line = $line -replace "(<code[^>]*) class=""[^""]*""", '$1'
        $line = $line -replace "<\/?span[^>]*>", ''
        $fixedHtmlContent += "$line`r`n"
    }
    $tmpHtml = "$tempFolder\$sourcePostPath.html.tmp"
    Write-Output "loading: $html -> $tmpHtml"
    Set-Content -Path $tmpHtml -Value $fixedHtmlContent
    Write-Output "converting: $tmpHtml -> $tmpMd"
    pandoc.exe --from=html --to=markdown --output=$tmpMd --wrap=preserve $tmpHtml
    $tmpContent = Get-Content $tmpMd
    $titleRegex = "## \[([^\]]+)\]\(\/blog\/$sourcePostPath\/\)"
    Select-String -InputObject $tmpContent -Pattern $titleRegex | ForEach-Object { 
        $titleTag = $_.Matches.Groups[1].Value
        Write-Output "title tag: $titleTag"
    }        
    $dateRegex = "[*]by Vitaly, [A-Z][a-z]+, ([A-Z][a-z]+ [0-9]{2})(st|th), (20[0-2][0-9])[*]"
    Select-String -InputObject $tmpContent -Pattern $dateRegex | ForEach-Object { 
        $dateString = "$($_.Matches.Groups[1].Value), $($_.Matches.Groups[3].Value)"
        # Write-Output "date string: $dateString"
        $dateTime = [datetime]$dateString
        # Write-Output "converted datetime: $dateTime"
        $dateTag = $dateTime.toString("yyyy-MM-dd")
        Write-Output "date tag: $dateTag"
        $dateDir = $dateTime.toString("yyyy\/MM\/dd\/")
        Write-Output "date dir: $dateDir"
    }
    $mdContent = "---`r`ntitle: ""$titleTag""`r`ntags:$tags`r`ncategories:$categories`r`ndate: $dateTag`r`n---`r`n"
    $postBegin = $false
    $postEnd = $false
    $codeBlock = $false
    foreach ($line in $tmpContent) {
        $isTitle = $false
        if (!$postEnd) {
            if (!$postBegin) {
                if ($line.StartsWith("## ")) {
                    $postBegin = $true
                    $isTitle = $true
                }
            }
            if ($postBegin) {
                if ($line -eq "------------------------------------------------------------------------") {
                    $postEnd = $true
                }
            }
        }
        if ($postBegin -and !$postEnd) {
            if ($isTitle) {
                $line = "## $titleTag"
            }
            else {
                if ($codeBlock) {
                    if ($line -match '^\s*:::\s*$') {
                        $line = $line -replace ':::', '```'
                        $codeBlock = $false
                    }
                }
                else {
                    if ($line -match '^\s*::: highlight\s*$') {
                        $line = $line -replace '::: highlight', '```'
                        $codeBlock = $true
                    }                 
                }         
                $mdContent += "$line`r`n"
            }
        }
    }
    $md = "source\_posts\$sourcePostPath.md"
    Write-Output "saving post: $md"
    Set-Content -Path $md -Value $mdContent
    $redirecContent = "---`r`ntitle: ""$titleTag""`r`nredirect: $dateDir/$sourcePostPath/`r`n---`r`n"
    $redirectDir = "source\$sourcePostPath"
    $redirectFilePath = "$redirectDir\index.md"
    if (-not (Test-Path -Path $redirectDir -PathType Container)) {
        Write-Output "creating redirect folder: $redirectDir"
        New-Item -Path $redirectDir -ItemType Directory
    } 
    else {
        Write-Output "redirect folder already exists: $redirectDir"
    }
    Write-Output "saving redirect: $redirectFilePath"
    Set-Content -Path $redirectFilePath -Value $redirecContent
}

Select-String -InputObject $categoryPathTitles -Pattern "\n([^\/]*)\/([^\n]*)" -AllMatches | ForEach-Object {
    foreach($m in $_.Matches) {
        $sourceCategoryPath = $m.Groups[1].Value
        $title = $m.Groups[2].Value
        $formattedTitle = $title -replace '\s', '-'
        Write-Output "source category: $title, path: $sourceCategoryPath"
        $redirecContent = "---`r`ntitle: ""$title""`r`nredirect: /categories/$formattedTitle/`r`n---`r`n"
        $redirectDir = "source\$sourceCategoryPath"
        $redirectFilePath = "$redirectDir\index.md"
        if (-not (Test-Path -Path $redirectDir -PathType Container)) {
            Write-Output "creating redirect folder: $redirectDir"
            New-Item -Path $redirectDir -ItemType Directory
        } 
        else {
            Write-Output "redirect folder already exists: $redirectDir"
        }
        Write-Output "saving redirect: $redirectFilePath"
        Set-Content -Path $redirectFilePath -Value $redirecContent
    }
}    

$sourceTagRegex = '^tag=([^&]*)(&.*)?$'
Get-ChildItem -Path $sourceDirectory | Where-Object {$_.Name -match $sourceTagRegex } | ForEach-Object {
    $sourceTagPath = $_.Name
    Select-String -InputObject $sourceTagPath -Pattern $sourceTagRegex | ForEach-Object { 
        $sourceTagValue = $_.Matches.Groups[1].Value
        $m = $tagPathText | Select-String -Pattern "\ntag=$sourceTagValue\/([^\n]+)\n"
        if ($m) {
            $targetTag = $m.Matches.Groups[1].Value -replace '\s', '-'
        }
        else {
            $targetTag = $sourceTagValue
        }
        Write-Output "source tag: $sourceTagValue, path: $sourceTagPath, target tag: $targetTag"
        $redirecContent = "---`r`ntitle: ""$sourceTagValue""`r`nredirect: /tags/$targetTag/`r`n---`r`n"
        $redirectDir = "source\$sourceTagPath"
        $redirectFilePath = "$redirectDir\index.md"
        if (-not (Test-Path -Path $redirectDir -PathType Container)) {
            Write-Output "creating redirect folder: $redirectDir"
            New-Item -Path $redirectDir -ItemType Directory
        } 
        else {
            Write-Output "redirect folder already exists: $redirectDir"
        }
        Write-Output "saving redirect: $redirectFilePath"
        Set-Content -Path $redirectFilePath -Value $redirecContent
    }
}

$sourceYearRegex = '^m=([1-9][0-9]{3})(&.*)?$'
Get-ChildItem -Path $sourceDirectory | Where-Object {$_.Name -match $sourceYearRegex } | ForEach-Object {
    $sourceYearPath = $_.Name
    Select-String -InputObject $sourceYearPath -Pattern $sourceYearRegex | ForEach-Object { 
        $sourceYear = $_.Matches.Groups[1].Value
        Write-Output "source year: $sourceYear, path: $sourceYearPath"
        $redirecContent = "---`r`ntitle: ""$sourceYear""`r`nredirect: /archives/$sourceYear/`r`n---`r`n"
        $redirectDir = "source\$sourceYearPath"
        $redirectFilePath = "$redirectDir\index.md"
        if (-not (Test-Path -Path $redirectDir -PathType Container)) {
            Write-Output "creating redirect folder: $redirectDir"
            New-Item -Path $redirectDir -ItemType Directory
        } 
        else {
            Write-Output "redirect folder already exists: $redirectDir"
        }
        Write-Output "saving redirect: $redirectFilePath"
        Set-Content -Path $redirectFilePath -Value $redirecContent
    }    
}

$sourceYearMonthRegex = '^m=([1-9][0-9]{3})([0-3][0-9])(&.*)?$'
Get-ChildItem -Path $sourceDirectory | Where-Object {$_.Name -match $sourceYearMonthRegex } | ForEach-Object {
    $sourceYearMonthPath = $_.Name
    Select-String -InputObject $sourceYearMonthPath -Pattern $sourceYearMonthRegex | ForEach-Object { 
        $sourceYear = $_.Matches.Groups[1].Value
        $sourceMonth = $_.Matches.Groups[2].Value
        Write-Output "source year/month: $sourceYear/$sourceMonth, path: $sourceYearMonthPath"
        $redirecContent = "---`r`ntitle: ""$sourceYear/$sourceMonth""`r`nredirect: /archives/$sourceYear/$sourceMonth/`r`n---`r`n"
        $redirectDir = "source\$sourceYearMonthPath"
        $redirectFilePath = "$redirectDir\index.md"
        if (-not (Test-Path -Path $redirectDir -PathType Container)) {
            Write-Output "creating redirect folder: $redirectDir"
            New-Item -Path $redirectDir -ItemType Directory
        } 
        else {
            Write-Output "redirect folder already exists: $redirectDir"
        }
        Write-Output "saving redirect: $redirectFilePath"
        Set-Content -Path $redirectFilePath -Value $redirecContent
    }    
}