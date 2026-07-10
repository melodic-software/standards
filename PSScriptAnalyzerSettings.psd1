# PSScriptAnalyzer settings — repo-agnostic PowerShell quality ruleset.
# OTBS (One True Brace Style) with strict, cross-platform rules. Targets
# PowerShell 7.4+ (the platform floor; no Windows PowerShell 5.1 consumers).
#
# The managed payload lives at a consuming repo's root, where PSScriptAnalyzer
# and editors discover it automatically. Consumers do not edit it in place.
# Severity below is the single source of truth for which findings block — the
# Invoke-ScriptAnalyzer -Settings docs give profile values precedence over the
# same parameters on the command line, so a conflicting CLI -Severity is
# ignored.
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

        # PSUseCompatibleSyntax is deliberately absent: it only flags syntax
        # NEWER than a targeted version (the rule doc's own example flags
        # ??/ternary only when 5.1-or-earlier targets are present), so with
        # this ruleset's 7.4+ floor and no 5.1/6.x consumers it can never
        # fire — verified empirically: a ??/ternary probe is flagged with a
        # 5.1 target and silent with 7.4/7.6. Re-add with TargetVersions if
        # a consumer ever needs a floor below the newest syntax-bearing
        # PowerShell release.

        # --- Best practices ---

        PSAvoidUsingCmdletAliases = @{
            Enable    = $true
            AllowList = @()
        }

        PSAvoidUsingDoubleQuotesForConstantString = @{
            Enable = $true
        }

        # Unused variables are bugs in automation scripts. A settings file
        # cannot re-map a rule's severity, so findings surface at the shipped
        # Warning — which the top-level Severity filter above lets block.
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
