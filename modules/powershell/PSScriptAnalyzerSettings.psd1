# PSScriptAnalyzer settings — repo-agnostic PowerShell quality ruleset.
# OTBS (One True Brace Style) with strict, cross-platform rules. Targets
# PowerShell 7.4+ (LTS) and 7.6+ (current).
#
# Adopt by copying this file to a consuming repo's root; PSScriptAnalyzer
# discovers a root-level PSScriptAnalyzerSettings.psd1 automatically, and
# editors (VS Code PowerShell extension) pick it up. Severity below is the
# single source of truth for which findings block — CLI -Severity is ignored
# when it conflicts with this file (Invoke-ScriptAnalyzer Example 8).
#
# Refs:
#   https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/rules/readme
#   https://github.com/PowerShell/PSScriptAnalyzer
#   https://github.com/PoshCode/PowerShellPracticeAndStyle

@{
    # Include Information so the Information-severity rules enabled below
    # (PSUseCorrectCasing, PSProvideCommentHelp,
    # PSAvoidUsingDoubleQuotesForConstantString) actually gate — a top-level
    # Severity filter discards any severity not listed here.
    Severity = @('Error', 'Warning', 'Information')

    ExcludeRules = @(
        # New-* helper functions that construct data objects (not system state
        # changes) trigger false positives. ShouldProcess is for Set/Remove, not
        # New-helpers.
        'PSUseShouldProcessForStateChangingFunctions'

        # PowerShell 7+ writes UTF-8 without BOM by default
        # (about_Character_Encoding) and the rest of a modern cross-platform
        # toolchain treats UTF-8 no-BOM as the default. The rule is a Windows
        # PowerShell 5.1 compatibility relic; 7.4+ targets put BOM-requiring 5.1
        # consumers out of scope.
        'PSUseBOMForUnicodeEncodedFile'
    )

    Rules = @{
        # --- Formatting: OTBS (One True Brace Style) ---

        PSPlaceOpenBrace = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }

        PSPlaceCloseBrace = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }

        PSUseConsistentIndentation = @{
            Enable              = $true
            Kind                = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize     = 4
        }

        PSUseConsistentWhitespace = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckPipe                               = $true
            CheckPipeForRedundantWhitespace         = $false
            CheckSeparator                          = $true
            CheckParameter                          = $false
            IgnoreAssignmentOperatorInsideHashTable = $true
        }

        PSAlignAssignmentStatement = @{
            Enable         = $false
            CheckHashtable = $false
        }

        PSUseCorrectCasing = @{
            Enable = $true
        }

        # Line length limit — PoshCode recommends 115; 120 matches common repo
        # conventions. Encourages splatting over backtick continuation.
        PSAvoidLongLines = @{
            Enable            = $true
            MaximumLineLength = 120
        }

        # Semicolons as line terminators are unnecessary in PowerShell and
        # complicate editing / source-control diffs (PoshCode recommendation).
        PSAvoidSemicolonsAsLineTerminators = @{
            Enable = $true
        }

        # --- Compatibility ---

        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.4', '7.6')
        }

        # --- Best practices ---

        PSAvoidUsingCmdletAliases = @{
            Enable    = $true
            AllowList = @()
        }

        PSAvoidUsingDoubleQuotesForConstantString = @{
            Enable = $true
        }

        # Unused variables are bugs in automation scripts — promote to Error.
        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }

        # Use -not instead of ! for readability — PowerShell idiom.
        PSAvoidExclaimOperator = @{
            Enable = $true
        }

        # Enforce param() blocks over inline parameters — aligns with the
        # [CmdletBinding()] param() script-header convention. Shipped in
        # PSScriptAnalyzer 1.25.0 (disabled by default).
        PSUseConsistentParametersKind = @{
            Enable         = $true
            ParametersKind = 'ParamBlock'
        }

        PSProvideCommentHelp = @{
            Enable                  = $true
            ExportedOnly            = $true
            BlockComment            = $true
            VSCodeSnippetCorrection = $false
            Placement               = 'begin'
        }
    }
}
