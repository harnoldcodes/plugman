# PlugMan

A PowerShell script for automatically downloading and installing VST3 and CLAP plugins from GitHub repositories.

## Features

- 🔽 **Automatic Downloads**: Fetches the latest release from GitHub repositories
- 🎛️ **Multi-Format Support**: Handles both VST3 and CLAP plugin formats
- 📦 **ZIP Archive Support**: Extracts plugins from Windows ZIP files when direct downloads aren't available
- 📋 **Batch Processing**: Process multiple repositories from a JSON configuration file
- 🔄 **Smart Overwrite**: Prompts before overwriting existing plugins (or use `-Force` to skip)
- 📍 **Flexible Path Configuration**: Set installation directories via command-line, environment variables, or config file
- 🎯 **Priority-Based Configuration**: Command-line parameters override environment variables, which override config file settings
- 🛡️ **Safe Installation**: Creates directories if they don't exist and validates paths

## Installation

1. Download `PlugMan.ps1` to your preferred directory
2. Ensure PowerShell execution policy allows script execution:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Usage

### Basic Usage

Install a plugin from a single GitHub repository:
```powershell
.\PlugMan.ps1 -Url "https://github.com/surge-synthesizer/surge"
```

### Batch Installation

Create a JSON configuration file with multiple repositories:
```powershell
.\PlugMan.ps1 -ConfigFile "C:\MyPlugins\config.json"
```

### Default Configuration

Run without parameters to use the default config file:
```powershell
.\PlugMan.ps1
```
This will look for `config.json` in `$env:USERPROFILE\.config\plugman\`

### Force Overwrite

Skip overwrite prompts for existing plugins:
```powershell
.\PlugMan.ps1 -Url "https://github.com/user/repo" -Force
```

## Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `-Url` | String | GitHub repository URL | None |
| `-ConfigFile` | String | Path to JSON configuration file | None |
| `-VST3_PATH` | String | VST3 installation directory (overrides all other sources) | See Path Priority |
| `-CLAP_PATH` | String | CLAP installation directory (overrides all other sources) | See Path Priority |
| `-Force` | Switch | Overwrite existing plugins without prompting | False |

## Configuration File Format

Create a JSON file with the following structure:

```json
{
  "urls": [
    "https://github.com/surge-synthesizer/surge",
    "https://github.com/DISTRHO/Cardinal",
    "https://github.com/VCVRack/Fundamental"
  ],
  "config": {
    "vst3_path": "C:\\My Custom Path\\VST3",
    "clap_path": "C:\\My Custom Path\\CLAP"
  }
}
```

### Configuration Sections

- **`urls`** (required): Array of GitHub repository URLs to process
- **`config`** (optional): Configuration section with custom installation paths
  - **`vst3_path`**: Custom VST3 installation directory
  - **`clap_path`**: Custom CLAP installation directory

### Default Configuration Location

If no parameters are provided, PlugMan looks for:
```
%USERPROFILE%\.config\plugman\config.json
```

Example: `C:\Users\YourName\.config\plugman\config.json`

## Path Configuration

PlugMan supports multiple ways to configure installation paths with the following priority order:

### Path Priority Order
1. **Command-line parameters** (`-VST3_PATH`, `-CLAP_PATH`) - Highest priority
2. **Environment variables** (`VST3_PATH`, `CLAP_PATH`) - Medium priority  
3. **Config file settings** (`config.vst3_path`, `config.clap_path`) - Low priority
4. **Default paths** - Lowest priority
   - VST3: `C:\Program Files\Common Files\VST3`
   - CLAP: `C:\Program Files\Common Files\CLAP`

### Environment Variables

You can set default installation paths using environment variables:

```powershell
# Set permanently
[Environment]::SetEnvironmentVariable("VST3_PATH", "D:\Audio\VST3", "User")
[Environment]::SetEnvironmentVariable("CLAP_PATH", "D:\Audio\CLAP", "User")

# Set for current session
$env:VST3_PATH = "D:\Audio\VST3"
$env:CLAP_PATH = "D:\Audio\CLAP"
```

## How It Works

1. **Repository Analysis**: Fetches the latest release from the GitHub API
2. **Direct Downloads**: Looks for `.vst3` and `.clap` files in release assets
3. **ZIP Fallback**: If no direct files found, downloads ZIP files containing "win" in the name
4. **Smart Extraction**: Recursively searches extracted content for plugin files
5. **Safe Installation**: Checks for existing plugins and prompts for overwrite (unless `-Force` is used)

## Examples

### Single Plugin Installation
```powershell
# Install Surge synthesizer
.\PlugMan.ps1 -Url "https://github.com/surge-synthesizer/surge"

# Install to custom directories
.\PlugMan.ps1 -Url "https://github.com/user/repo" -VST3_PATH "D:\VST3" -CLAP_PATH "D:\CLAP"

# Force overwrite existing plugins
.\PlugMan.ps1 -Url "https://github.com/user/repo" -Force
```

### Batch Installation
```powershell
# Use custom config file
.\PlugMan.ps1 -ConfigFile "D:\MyStudio\essential-plugins.json"

# Batch install with force overwrite
.\PlugMan.ps1 -ConfigFile "plugins.json" -Force
```

### Sample Configuration Files

#### Basic Configuration
Create `essential-plugins.json`:
```json
{
  "urls": [
    "https://github.com/surge-synthesizer/surge",
    "https://github.com/DISTRHO/Cardinal",
    "https://github.com/michaeldonovan/mbdsp",
    "https://github.com/TheBoulder/Odin2"
  ]
}
```

#### Configuration with Custom Paths
Create `studio-setup.json`:
```json
{
  "urls": [
    "https://github.com/surge-synthesizer/surge",
    "https://github.com/DISTRHO/Cardinal"
  ],
  "config": {
    "vst3_path": "D:\\Audio Software\\VST3 Plugins",
    "clap_path": "D:\\Audio Software\\CLAP Plugins"
  }
}
```

Then run:
```powershell
# Basic config
.\PlugMan.ps1 -ConfigFile "essential-plugins.json"

# Config with custom paths
.\PlugMan.ps1 -ConfigFile "studio-setup.json"
```

## Supported Plugin Formats

- **VST3**: Installed to VST3_PATH (default: `C:\Program Files\Common Files\VST3`)
- **CLAP**: Installed to CLAP_PATH (default: `C:\Program Files\Common Files\CLAP`)

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Internet connection for GitHub API access
- Administrator privileges may be required for default installation paths

## Error Handling

- **Missing Config**: Shows usage help and suggests creating a config file
- **Invalid URLs**: Skips invalid repositories and continues with others
- **Network Issues**: Reports download failures and continues with remaining plugins
- **Permission Issues**: Reports installation failures with clear error messages

## Troubleshooting

### Permission Errors
If you get permission errors when installing to default paths, try:
1. Run PowerShell as Administrator, or
2. Use custom installation paths in user directories:
   ```powershell
   .\PlugMan.ps1 -Url "..." -VST3_PATH "$env:USERPROFILE\VST3" -CLAP_PATH "$env:USERPROFILE\CLAP"
   ```

### Execution Policy Errors
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### GitHub API Rate Limits
If you hit GitHub's rate limit, wait an hour or authenticate with GitHub CLI.

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is open source and available under the MIT License.