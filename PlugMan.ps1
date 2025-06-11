param(
    [Parameter(Mandatory=$false)]
    [string]$Url,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile,
    
    [string]$VST3_PATH,
    [string]$CLAP_PATH,
    [string]$BWPRESET_PATH,
    
    [switch]$Force
)

function Show-Usage {
    Write-Host @"
PlugMan - VST3/CLAP Plugin Manager

USAGE:
    PlugMan.ps1 -Url <GitHubRepoUrl|DirectFileUrl> [-Force]
    PlugMan.ps1 -ConfigFile <path> [-Force]

PARAMETERS:
    -Url            Install from a GitHub repository URL or direct file URL
                    Repository: https://github.com/user/repo
                    Direct file: https://example.com/plugin.vst3 (.vst3, .clap, .bwpreset, .zip)
    -ConfigFile     Path to JSON config file containing multiple plugin definitions
    -Force          Overwrite existing plugins without prompting

ENVIRONMENT VARIABLES:
    VST3_PATH      VST3 installation directory (default: C:\Program Files\Common Files\VST3)
    CLAP_PATH      CLAP installation directory (default: C:\Program Files\Common Files\CLAP)
    BWPRESET_PATH  BWPreset installation directory (default: %USERPROFILE%\Documents\Bitwig Studio\Presets)

PATH PRIORITY ORDER:
    1. Environment variables (VST3_PATH, CLAP_PATH, BWPRESET_PATH)
    2. Config file 'config' section (vst3_path, clap_path, bwpreset_path)  
    3. Default paths

EXAMPLES:
    PlugMan.ps1 -Url "https://github.com/surge-synthesizer/surge"
    PlugMan.ps1 -Url "https://example.com/plugin.vst3"
    PlugMan.ps1 -Url "https://example.com/presets.zip"
    PlugMan.ps1 -ConfigFile "C:\MyPlugins\config.json"
    PlugMan.ps1 -Force

CONFIG FILE FORMAT (JSON):
    {
        "urls": [
            "https://github.com/user/repo1",
            "https://github.com/user/repo2"
        ],
        "config": {
            "vst3_path": "C:\\My Custom Path\\VST3",
            "clap_path": "C:\\My Custom Path\\CLAP",
            "bwpreset_path": "C:\\My Custom Path\\BWPresets"
        }
    }

DEFAULT CONFIG LOCATION:
    $env:USERPROFILE\.config\plugman\config.json

"@ -ForegroundColor Yellow
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Initialize-Paths {
    param([object]$Config = $null)
    
    # Initialize VST3_PATH with priority: env var > config > default
    if (-not $script:VST3_PATH) {
        if ($env:VST3_PATH) {
            $script:VST3_PATH = $env:VST3_PATH
            Write-Log "Using VST3_PATH from environment variable: $script:VST3_PATH"
        } elseif ($Config -and $Config.vst3_path) {
            $script:VST3_PATH = $Config.vst3_path
            Write-Log "Using VST3_PATH from config file: $script:VST3_PATH"
        } else {
            $script:VST3_PATH = "C:\Program Files\Common Files\VST3"
            Write-Log "Using default VST3_PATH: $script:VST3_PATH"
        }
    }
    
    # Initialize CLAP_PATH with priority: env var > config > default
    if (-not $script:CLAP_PATH) {
        if ($env:CLAP_PATH) {
            $script:CLAP_PATH = $env:CLAP_PATH
            Write-Log "Using CLAP_PATH from environment variable: $script:CLAP_PATH"
        } elseif ($Config -and $Config.clap_path) {
            $script:CLAP_PATH = $Config.clap_path
            Write-Log "Using CLAP_PATH from config file: $script:CLAP_PATH"
        } else {
            $script:CLAP_PATH = "C:\Program Files\Common Files\CLAP"
            Write-Log "Using default CLAP_PATH: $script:CLAP_PATH"
        }
    }
    
    # Initialize BWPRESET_PATH with priority: env var > config > default
    if (-not $script:BWPRESET_PATH) {
        if ($env:BWPRESET_PATH) {
            $script:BWPRESET_PATH = $env:BWPRESET_PATH
            Write-Log "Using BWPRESET_PATH from environment variable: $script:BWPRESET_PATH"
        } elseif ($Config -and $Config.bwpreset_path) {
            $script:BWPRESET_PATH = $Config.bwpreset_path
            Write-Log "Using BWPRESET_PATH from config file: $script:BWPRESET_PATH"
        } else {
            $script:BWPRESET_PATH = Join-Path $env:USERPROFILE "Documents\Bitwig Studio\Presets"
            Write-Log "Using default BWPRESET_PATH: $script:BWPRESET_PATH"
        }
    }
}

function Test-Paths {
    $errors = @()
    
    if (-not $script:VST3_PATH) {
        $errors += "VST3_PATH not specified. Set environment variable or define in config.json."
    } elseif (-not (Test-Path $script:VST3_PATH)) {
        try {
            New-Item -ItemType Directory -Path $script:VST3_PATH -Force | Out-Null
            Write-Log "Created VST3 directory: $script:VST3_PATH"
        } catch {
            $errors += "Cannot create VST3_PATH directory: $script:VST3_PATH"
        }
    }
    
    if (-not $script:CLAP_PATH) {
        $errors += "CLAP_PATH not specified. Set environment variable or define in config.json."
    } elseif (-not (Test-Path $script:CLAP_PATH)) {
        try {
            New-Item -ItemType Directory -Path $script:CLAP_PATH -Force | Out-Null
            Write-Log "Created CLAP directory: $script:CLAP_PATH"
        } catch {
            $errors += "Cannot create CLAP_PATH directory: $script:CLAP_PATH"
        }
    }
    
    if (-not $script:BWPRESET_PATH) {
        $errors += "BWPRESET_PATH not specified. Set environment variable or define in config.json."
    } elseif (-not (Test-Path $script:BWPRESET_PATH)) {
        try {
            New-Item -ItemType Directory -Path $script:BWPRESET_PATH -Force | Out-Null
            Write-Log "Created BWPreset directory: $script:BWPRESET_PATH"
        } catch {
            $errors += "Cannot create BWPRESET_PATH directory: $script:BWPRESET_PATH"
        }
    }
    
    if ($errors.Count -gt 0) {
        foreach ($error in $errors) {
            Write-Log $error "ERROR"
        }
        exit 1
    }
}

function Get-UrlType {
    param([string]$Url)
    
    # Check if it's a direct file URL
    if ($Url -match '\.(zip|vst3|clap|bwpreset)(\?.*)?$') {
        $extension = $matches[1].ToLower()
        return @{
            Type = "DirectFile"
            FileType = $extension
            Url = $Url
        }
    }
    
    # Check if it's a GitHub repository URL
    if ($Url -match "github\.com/([^/]+)/([^/]+)") {
        return @{
            Type = "Repository"
            Owner = $matches[1]
            Repo = $matches[2].TrimEnd('.git')
            Url = $Url
        }
    }
    
    throw "Invalid URL format. Must be either a GitHub repository URL or a direct file URL (.zip, .vst3, .clap, .bwpreset)"
}

function Get-RepoInfo {
    param([string]$RepoUrl)
    
    if ($RepoUrl -match "github\.com/([^/]+)/([^/]+)") {
        return @{
            Owner = $matches[1]
            Repo = $matches[2].TrimEnd('.git')
        }
    } else {
        throw "Invalid GitHub repository URL format"
    }
}

function Get-LatestRelease {
    param([string]$Owner, [string]$Repo)
    
    $apiUrl = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers @{
            "User-Agent" = "PlugMan/1.0"
        }
        return $response
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            throw "Repository not found or no releases available"
        } else {
            throw "Failed to fetch release information: $($_.Exception.Message)"
        }
    }
}

function Get-FileFromUrl {
    param([string]$Url, [string]$OutputPath)
    
    try {
        Write-Log "Downloading: $Url"
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UserAgent "PlugMan/1.0"
        Write-Log "Downloaded to: $OutputPath"
        return $true
    } catch {
        Write-Log "Failed to download $Url`: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Expand-ZipFile {
    param([string]$ZipPath, [string]$ExtractPath)
    
    try {
        Write-Log "Extracting: $ZipPath"
        if (Test-Path $ExtractPath) {
            Remove-Item $ExtractPath -Recurse -Force
        }
        Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force
        Write-Log "Extracted to: $ExtractPath"
        return $true
    } catch {
        Write-Log "Failed to extract $ZipPath`: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Install-Plugin {
    param([string]$SourcePath, [string]$DestinationPath, [string]$PluginType, [bool]$Force = $false)
    
    try {
        if (Test-Path $DestinationPath) {
            $pluginName = Split-Path $DestinationPath -Leaf
            Write-Log "Plugin already exists: $pluginName" "WARNING"
            
            if (-not $Force -and -not $script:ForceAll) {
                do {
                    $response = Read-Host "Overwrite existing $PluginType plugin '$pluginName'? (y/n/a) [n]"
                    if ([string]::IsNullOrWhiteSpace($response)) {
                        $response = 'n'  # Default to 'n' when Enter is pressed
                    }
                    $response = $response.ToLower()
                } while ($response -ne 'y' -and $response -ne 'n' -and $response -ne 'yes' -and $response -ne 'no' -and $response -ne 'a' -and $response -ne 'all')
                
                if ($response -eq 'a' -or $response -eq 'all') {
                    $script:ForceAll = $true
                    Write-Log "Setting force overwrite for all remaining plugins" "INFO"
                } elseif ($response -eq 'n' -or $response -eq 'no') {
                    Write-Log "Skipping installation of $PluginType plugin: $pluginName" "INFO"
                    return $true
                }
            } else {
                if ($Force) {
                    Write-Log "Force flag specified, overwriting without prompt" "INFO"
                } else {
                    Write-Log "Force all flag active, overwriting without prompt" "INFO"
                }
            }
            
            Write-Log "Removing existing $PluginType plugin: $DestinationPath"
            Remove-Item $DestinationPath -Recurse -Force
        }
        
        Copy-Item $SourcePath $DestinationPath -Recurse -Force
        Write-Log "Installed $PluginType plugin: $DestinationPath" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to install $PluginType plugin: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Read-PluginConfig {
    param([string]$ConfigPath)
    
    try {
        if (-not (Test-Path $ConfigPath)) {
            throw "Config file not found: $ConfigPath"
        }
        
        $jsonContent = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        
        if (-not $jsonContent.urls) {
            throw "No 'urls' property found in config file"
        }
        
        $urls = @($jsonContent.urls)
        
        if ($urls.Count -eq 0) {
            throw "No URLs found in config file"
        }
        
        $result = @{
            urls = $urls
            config = $null
        }
        
        # Check for config section first
        if ($jsonContent.config) {
            $result.config = $jsonContent.config
            Write-Log "Found config section in config file"
        }
        # Also check for paths at root level for backward compatibility
        elseif ($jsonContent.vst3_path -or $jsonContent.clap_path -or $jsonContent.bwpreset_path) {
            $result.config = @{}
            if ($jsonContent.vst3_path) { $result.config.vst3_path = $jsonContent.vst3_path }
            if ($jsonContent.clap_path) { $result.config.clap_path = $jsonContent.clap_path }
            if ($jsonContent.bwpreset_path) { $result.config.bwpreset_path = $jsonContent.bwpreset_path }
            Write-Log "Found path configuration at root level in config file"
        }
        
        Write-Log "Found $($urls.Count) URLs in config file"
        return $result
        
    } catch {
        throw "Failed to read config file: $($_.Exception.Message)"
    }
}

function Install-DirectFileUrl {
    param([string]$Url, [string]$FileType, [bool]$Force = $false)
    
    try {
        $tempDir = Join-Path $env:TEMP "PlugMan_DirectFile_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        # Extract filename from URL
        $uri = [System.Uri]$Url
        $fileName = Split-Path $uri.LocalPath -Leaf
        if (-not $fileName -or $fileName -eq "/") {
            $fileName = "download.$FileType"
        }
        
        $downloadPath = Join-Path $tempDir $fileName
        Write-Log "Processing direct file URL: $Url"
        
        if (-not (Get-FileFromUrl -Url $Url -OutputPath $downloadPath)) {
            throw "Failed to download file from $Url"
        }
        
        $success = $false
        
        switch ($FileType) {
            "vst3" {
                $destinationPath = Join-Path $script:VST3_PATH $fileName
                $success = Install-Plugin -SourcePath $downloadPath -DestinationPath $destinationPath -PluginType "VST3" -Force $Force
                if ($success) { Write-Log "VST3 plugin installed to: $script:VST3_PATH" }
            }
            "clap" {
                $destinationPath = Join-Path $script:CLAP_PATH $fileName
                $success = Install-Plugin -SourcePath $downloadPath -DestinationPath $destinationPath -PluginType "CLAP" -Force $Force
                if ($success) { Write-Log "CLAP plugin installed to: $script:CLAP_PATH" }
            }
            "bwpreset" {
                $destinationPath = Join-Path $script:BWPRESET_PATH $fileName
                $success = Install-Plugin -SourcePath $downloadPath -DestinationPath $destinationPath -PluginType "BWPreset" -Force $Force
                if ($success) { Write-Log "BWPreset file installed to: $script:BWPRESET_PATH" }
            }
            "zip" {
                $extractPath = Join-Path $tempDir "extracted"
                if (Expand-ZipFile -ZipPath $downloadPath -ExtractPath $extractPath) {
                    $plugins = Find-PluginsInDirectory -Directory $extractPath
                    
                    $vst3Found = $false
                    $clapFound = $false
                    $bwpresetFound = $false
                    
                    foreach ($vst3Plugin in $plugins.VST3) {
                        $pluginName = Split-Path $vst3Plugin -Leaf
                        $destinationPath = Join-Path $script:VST3_PATH $pluginName
                        if (Install-Plugin -SourcePath $vst3Plugin -DestinationPath $destinationPath -PluginType "VST3" -Force $Force) {
                            $vst3Found = $true
                        }
                    }
                    
                    foreach ($clapPlugin in $plugins.CLAP) {
                        $pluginName = Split-Path $clapPlugin -Leaf
                        $destinationPath = Join-Path $script:CLAP_PATH $pluginName
                        if (Install-Plugin -SourcePath $clapPlugin -DestinationPath $destinationPath -PluginType "CLAP" -Force $Force) {
                            $clapFound = $true
                        }
                    }
                    
                    foreach ($bwpresetPlugin in $plugins.BWPRESET) {
                        $pluginName = Split-Path $bwpresetPlugin -Leaf
                        $destinationPath = Join-Path $script:BWPRESET_PATH $pluginName
                        if (Install-Plugin -SourcePath $bwpresetPlugin -DestinationPath $destinationPath -PluginType "BWPreset" -Force $Force) {
                            $bwpresetFound = $true
                        }
                    }
                    
                    if ($vst3Found -or $clapFound -or $bwpresetFound) {
                        $success = $true
                        if ($vst3Found) { Write-Log "VST3 plugins installed to: $script:VST3_PATH" }
                        if ($clapFound) { Write-Log "CLAP plugins installed to: $script:CLAP_PATH" }
                        if ($bwpresetFound) { Write-Log "BWPreset files installed to: $script:BWPRESET_PATH" }
                    } else {
                        Write-Log "No plugins found in ZIP file" "ERROR"
                    }
                } else {
                    throw "Failed to extract ZIP file"
                }
            }
        }
        
        # Clean up temp directory
        if ($tempDir -and (Test-Path $tempDir)) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        return $success
        
    } catch {
        Write-Log "Failed to process direct file URL: $($_.Exception.Message)" "ERROR"
        
        # Clean up temp directory on error
        if ($tempDir -and (Test-Path $tempDir)) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        return $false
    }
}

function Find-PluginsInDirectory {
    param([string]$Directory)
    
    $plugins = @{
        VST3 = @()
        CLAP = @()
        BWPRESET = @()
    }
    
    Get-ChildItem -Path $Directory -Recurse -File | ForEach-Object {
        if ($_.Extension -eq ".vst3") {
            $plugins.VST3 += $_.FullName
        } elseif ($_.Extension -eq ".clap") {
            $plugins.CLAP += $_.FullName
        } elseif ($_.Extension -eq ".bwpreset") {
            $plugins.BWPRESET += $_.FullName
        }
    }
    
    return $plugins
}

# Parameter validation
if ($Url -and $ConfigFile) {
    Write-Host "ERROR: Cannot specify both -Url and -ConfigFile parameters. Use only one." -ForegroundColor Red
    Show-Usage
    exit 1
}

# Global variable to track if user selected "all" for overwrite prompts
$script:ForceAll = $false

Write-Log "PlugMan - VST3/CLAP Plugin Manager"

# Determine URLs to process
$urlsToProcess = @()
$configData = $null

try {
    if ($Url) {
        Write-Log "Processing single URL: $Url"
        $urlsToProcess = @($Url)
        
        # Check for default config file to get path configuration
        $defaultConfigPath = Join-Path $env:USERPROFILE ".config\plugman\config.json"
        if (Test-Path $defaultConfigPath) {
            try {
                $configData = Read-PluginConfig -ConfigPath $defaultConfigPath
                Write-Log "Using path configuration from default config file: $defaultConfigPath"
                Initialize-Paths -Config $configData.config
            } catch {
                Write-Log "Warning: Could not read default config file for path configuration: $($_.Exception.Message)" "WARNING"
                Initialize-Paths
            }
        } else {
            Initialize-Paths
        }
    } elseif ($ConfigFile) {
        Write-Log "Reading URLs from config file: $ConfigFile"
        $configData = Read-PluginConfig -ConfigPath $ConfigFile
        $urlsToProcess = $configData.urls
        Initialize-Paths -Config $configData.config
    } else {
        # Default config file path
        $defaultConfigPath = Join-Path $env:USERPROFILE ".config\plugman\config.json"
        Write-Log "No URL or ConfigFile specified, checking default config: $defaultConfigPath"
        
        if (Test-Path $defaultConfigPath) {
            $configData = Read-PluginConfig -ConfigPath $defaultConfigPath
            $urlsToProcess = $configData.urls
            Initialize-Paths -Config $configData.config
        } else {
            Write-Host "`nNo URL specified and no default config file found." -ForegroundColor Red
            Write-Host "Please either:" -ForegroundColor Yellow
            Write-Host "  1. Provide a URL: PlugMan.ps1 -Url 'https://github.com/user/repo'" -ForegroundColor Yellow
            Write-Host "  2. Create a config file at: $defaultConfigPath" -ForegroundColor Yellow
            Write-Host ""
            Show-Usage
            exit 1
        }
    }
} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Show-Usage
    exit 1
}

Test-Paths

try {
    foreach ($currentUrl in $urlsToProcess) {
        Write-Log "Processing URL: $currentUrl"
        
        # Detect URL type
        try {
            $urlInfo = Get-UrlType -Url $currentUrl
        } catch {
            Write-Log "Error: $($_.Exception.Message)" "ERROR"
            continue
        }
        
        if ($urlInfo.Type -eq "DirectFile") {
            Write-Log "Processing direct file URL (.$($urlInfo.FileType))"
            $success = Install-DirectFileUrl -Url $currentUrl -FileType $urlInfo.FileType -Force $Force
            
            if ($success) {
                Write-Log "Direct file installation completed for $currentUrl!" "SUCCESS"
            } else {
                Write-Log "Failed to install file from $currentUrl" "ERROR"
            }
            continue
        }
        
        # Repository processing (existing logic)
        Write-Log "Processing GitHub repository: $currentUrl"
        $repoInfo = Get-RepoInfo -RepoUrl $currentUrl
        Write-Log "Repository: $($repoInfo.Owner)/$($repoInfo.Repo)"
        
        $release = Get-LatestRelease -Owner $repoInfo.Owner -Repo $repoInfo.Repo
        Write-Log "Latest release: $($release.tag_name) - $($release.name)"
        
        $tempDir = Join-Path $env:TEMP "PlugMan_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        $vst3Found = $false
        $clapFound = $false
        $bwpresetFound = $false
    
        foreach ($asset in $release.assets) {
            Write-Log "Found asset: $($asset.name)"
            
            if ($asset.name -like "*.vst3") {
                $downloadPath = Join-Path $tempDir $asset.name
                if (Get-FileFromUrl -Url $asset.browser_download_url -OutputPath $downloadPath) {
                    $destinationPath = Join-Path $script:VST3_PATH $asset.name
                    Install-Plugin -SourcePath $downloadPath -DestinationPath $destinationPath -PluginType "VST3" -Force $Force
                    $vst3Found = $true
                }
            } elseif ($asset.name -like "*.clap") {
                $downloadPath = Join-Path $tempDir $asset.name
                if (Get-FileFromUrl -Url $asset.browser_download_url -OutputPath $downloadPath) {
                    $destinationPath = Join-Path $script:CLAP_PATH $asset.name
                    Install-Plugin -SourcePath $downloadPath -DestinationPath $destinationPath -PluginType "CLAP" -Force $Force
                    $clapFound = $true
                }
            } elseif ($asset.name -like "*.bwpreset") {
                $downloadPath = Join-Path $tempDir $asset.name
                if (Get-FileFromUrl -Url $asset.browser_download_url -OutputPath $downloadPath) {
                    $destinationPath = Join-Path $script:BWPRESET_PATH $asset.name
                    Install-Plugin -SourcePath $downloadPath -DestinationPath $destinationPath -PluginType "BWPreset" -Force $Force
                    $bwpresetFound = $true
                }
            }
        }
    
        if (-not $vst3Found -and -not $clapFound -and -not $bwpresetFound) {
            Write-Log "No direct VST3/CLAP/BWPreset files found. Looking for ZIP files with 'win' in name..."
            
            $winZips = $release.assets | Where-Object { $_.name -like "*.zip" -and $_.name -like "*win*" }
            
            if ($winZips.Count -eq 0) {
                Write-Log "No ZIP files with 'win' in name found for $currentUrl" "ERROR"
                continue
            }
            
            foreach ($zipAsset in $winZips) {
                Write-Log "Processing ZIP file: $($zipAsset.name)"
                
                $zipPath = Join-Path $tempDir $zipAsset.name
                $extractPath = Join-Path $tempDir "extracted_$($zipAsset.name -replace '\.zip$', '')"
                
                if (Get-FileFromUrl -Url $zipAsset.browser_download_url -OutputPath $zipPath) {
                    if (Expand-ZipFile -ZipPath $zipPath -ExtractPath $extractPath) {
                        $plugins = Find-PluginsInDirectory -Directory $extractPath
                        
                        foreach ($vst3Plugin in $plugins.VST3) {
                            $pluginName = Split-Path $vst3Plugin -Leaf
                            $destinationPath = Join-Path $script:VST3_PATH $pluginName
                            Install-Plugin -SourcePath $vst3Plugin -DestinationPath $destinationPath -PluginType "VST3" -Force $Force
                            $vst3Found = $true
                        }
                        
                        foreach ($clapPlugin in $plugins.CLAP) {
                            $pluginName = Split-Path $clapPlugin -Leaf
                            $destinationPath = Join-Path $script:CLAP_PATH $pluginName
                            Install-Plugin -SourcePath $clapPlugin -DestinationPath $destinationPath -PluginType "CLAP" -Force $Force
                            $clapFound = $true
                        }
                        
                        foreach ($bwpresetPlugin in $plugins.BWPRESET) {
                            $pluginName = Split-Path $bwpresetPlugin -Leaf
                            $destinationPath = Join-Path $script:BWPRESET_PATH $pluginName
                            Install-Plugin -SourcePath $bwpresetPlugin -DestinationPath $destinationPath -PluginType "BWPreset" -Force $Force
                            $bwpresetFound = $true
                        }
                    }
                }
            }
        }
    
        if ($vst3Found -or $clapFound -or $bwpresetFound) {
            Write-Log "Plugin installation completed for $currentUrl!" "SUCCESS"
            if ($vst3Found) { Write-Log "VST3 plugins installed to: $script:VST3_PATH" }
            if ($clapFound) { Write-Log "CLAP plugins installed to: $script:CLAP_PATH" }
            if ($bwpresetFound) { Write-Log "BWPreset files installed to: $script:BWPRESET_PATH" }
        } else {
            Write-Log "No VST3, CLAP, or BWPreset files found for $currentUrl" "ERROR"
        }
        
        # Clean up temp directory for this repository
        if ($tempDir -and (Test-Path $tempDir)) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Log "All repositories processed successfully!" "SUCCESS"
    
} catch {
    Write-Log "Error: $($_.Exception.Message)" "ERROR"
    exit 1
}