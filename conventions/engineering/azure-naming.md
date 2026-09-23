# Azure resource naming and tagging

How Melodic Software names and tags Azure resources. Every rule below either cites its source or is labeled judgment. This file states the rule and the organization's token values; which resources exist and what they are called is recorded by the repository that governs them, in its own naming decision record, which links here and states any deviation.

## Tokens

| Token | Value |
|---|---|
| `<org>` | `melo` |
| `<env>` | `prod`, `dev` or `test` |
| `<region>` | `usc` (Central US), `use2` (East US 2); used only once the estate spans a second region |
| `<nnn>` | a three-digit instance suffix, starting at `001` |
| `<workload>` | what the resource is for |
| `<consumer>` | the identity that reads a key vault |

## Patterns by resource type

| Resource type | Pattern | Example |
|---|---|---|
| Subscription display name | `Melodic Software` | |
| Resource group | `rg-<workload>-<env>` | `rg-billing-prod` |
| Key vault | `kv-melo-<consumer>-<env>` | `kv-melo-billing-prod` |
| Log Analytics workspace | `log-<workload>-<env>` | `log-billing-prod` |
| Storage account | `stmelo<workload>` or `stmelo<workload><nnn>` | `stmeloreports001` |
| Blob container | `<workload>` or `<workload>-<nnn>` | `invoices` |

The example workloads are illustrative, not resources that exist.

Before creating a resource, check the name against the type's current uniqueness scope, length and
character set in Microsoft's
[naming rules and restrictions](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules).
Those limits are Azure's to change, so this file does not copy them. Length and character limits
for a subscription display name are not published on any Microsoft page located, so treat a plain
ASCII phrase as the safe shape (judgment).

The abbreviations `rg`, `kv`, `log`, `st` come from
<https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations>.
They are bare tokens; the hyphen comes from the delimiter rule below, not from the abbreviation.
That page carries no subscription row and no blob-container row, so those two patterns are
judgment.

### The hyphen rule

Use a hyphen between naming components wherever the resource type permits one, and nothing where it
does not. That is why a storage account name runs the components together: the type forbids
hyphens outright. Microsoft states it directly: "To improve readability, use a hyphen `-` to
separate naming components. However, not every resource in Azure allows you to use a delimiter."
<https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming>

### The organization token

`melo` appears only inside names that must be globally unique, which for these types means key
vaults and storage accounts. Names scoped to the subscription or to a parent resource already have
uniqueness and the token only spends characters. The globally unique types also carry the
tightest length limits among these types, so the token budget is tightest exactly where it is needed
(<https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/resource-name-rules>).
That the token buys nothing on a subscription-scoped name is judgment.

### No personal tokens

No name carries a person's name or initials. Microsoft's ban covers names and tags alike: "Don't
include any personal, sensitive, or confidential information in resource names (for example, table
name, database name) and resource tags. Data you enter in these fields isn't considered customer
data."
(<https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming>).
Most of these types cannot be renamed (see name permanence below), so an initial outlives the
person's involvement.

### Environment tokens

`prod`, `dev`, `test`, one of the three, spelled out that way. Use the token only where the
environment it names is real. A `dev` token asserts a `prod` sibling; if no sibling exists, the
token describes the estate falsely. A resource that production depends on is `prod`, whatever it
was created as. Judgment.

Storage account names omit the environment token: Microsoft's own storage example carries a
workload, a data descriptor and an instance number with no environment component
(<https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming>).
Applying that exception rather than forcing consistency is judgment.

### Region tokens

While the estate is single-region, no name carries a region token. When a second region arrives,
take short names from the Azure Naming Tool's `resourcelocations.json`, the only Microsoft-hosted
machine-readable set located: Central US is `usc` and East US 2 is `use2`
(<https://github.com/Azure/AzureNamingTool/blob/main/src/repository/resourcelocations.json>,
verified 2026-09-23; recheck when a commit touches that file). The common community family, which
writes the same two regions `cus` and `eus2`, is rejected. Microsoft publishes no official region
abbreviation list, so both families look obviously correct to different readers and the only
defense is picking one in advance and writing down which. Judgment.

In a multi-region estate, a resource created in a second region appends `-<region>` after `<env>`
(for example `rg-billing-prod-use2`), and only on types that permit a hyphen. Existing names stay
as they are, since most of these types cannot be renamed (see name permanence below), and the
`region` tag stays the authoritative record of where every resource lives. Judgment.

### Instance suffixes

Add `<nnn>` only where a second instance of the same resource is plausible. A suffix on a singleton
is a promise the estate never keeps. Judgment.

### Name permanence

Put in the name only what will never change about the resource, and put everything else in a tag.
Microsoft's rule: "include only information that remains constant in the name, use tags to capture
other details"
(<https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming>).
This is the affirmative reason a single-region estate keeps the region in the `region` tag rather
than in the name, and it matters because most of these types cannot be renamed at all: resource
groups, key vaults, storage accounts and blob containers are all immutable once created, and only a
subscription display name can be changed in place
(<https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/frequently-asked-questions>).
A deleted key vault's name stays blocked for the whole soft-delete retention period, up to 90 days
(<https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview>).

## The consumer-split rule

A key vault's workload token names its **consumer**, not its contents: `kv-melo-<consumer>-<env>`,
never `kv-melo-secrets-<env>`. A vault obviously holds secrets, so `secrets` as a workload token
tells a reader nothing, while the consumer is the boundary Microsoft states:

> consider what secrets a specific application should have access to, and then separate your key
> vaults based on this delineation

<https://learn.microsoft.com/en-us/azure/key-vault/general/secure-key-vault>

Extra vaults carry no standing charge (same source, verified 2026-09-23; recheck against
<https://azure.microsoft.com/en-us/pricing/details/key-vault/> before splitting a vault), so the
split costs configuration effort rather than money.

The one documented exception is a resource group whose job is lifecycle co-location of several
vaults. A resource group groups by shared lifecycle, not by classification, so such a group names
the plane it serves rather than any one consumer
(<https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/overview>).

## The nonsecret-placement rule

A value's home is decided by who consumes it, not by how sensitive it feels. A nonsecret is
information whose leak does not jeopardize the workload's security posture, and the guidance is
explicit that you should not treat nonsecrets like secrets
(<https://learn.microsoft.com/en-us/azure/well-architected/security/application-secrets>).

| Value type | Home | Reason | Source |
|---|---|---|---|
| Public identifier consumed by CI | Organization-level Actions variable, read as `vars.*` | The issuer's own instruction is to store an application's client ID as a configuration variable and only its private key as a secret | <https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow> |
| Public identifier consumed by infrastructure code | Plain committed key in the stack configuration file | Stack configuration files are meant to be committed, and encryption is opt-in per value rather than the default | <https://www.pulumi.com/docs/iac/concepts/secrets/> |
| Public identifier consumed by a workstation tool | Committed structured-data file in the dotfiles repository | Static data files cannot be templates, so they cannot route through a secret resolver, which makes them the correct side of the boundary for identifiers | <https://www.chezmoi.io/reference/special-files/chezmoidata-format/> |
| Runtime feature flag or runtime application setting | A configuration service, once a runtime reader exists | Every capability a configuration service charges for presumes an application reading settings at run time; without one it is a paid indirection with a manual write path | <https://learn.microsoft.com/en-us/azure/azure-app-configuration/overview> |
| A true secret | Key vault, in the vault whose consumer reads it | The vault is the security boundary and the place access control is assigned | <https://learn.microsoft.com/en-us/azure/key-vault/general/secure-key-vault> |

No located source prohibits parking a nonsecret in a vault, so moving one out is a tidiness
decision rather than a compliance one. Judgment.

## The fleet rule

Device hostnames never become Azure resource-name tokens. A hostname names a directory device
object, not an Azure resource: devices are Microsoft Entra device objects reached through Graph,
and they do not appear in Azure's resource taxonomy at all
(<https://learn.microsoft.com/en-us/entra/identity/devices/overview>). A hostname inside a resource
name invites a reader to go looking for that machine in the portal, where it does not exist.
Judgment. A hostname may still appear inside a secret's object name, where the secret is genuinely
about that host.

## Tags

Seven tags, on every resource group and every resource that supports tags. Blob containers do not
support Azure Resource Manager tags (container metadata is a separate facility), so a container is
covered by its storage account's tags
(<https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/tag-support>).

| Tag | Value |
|---|---|
| `workload` | the workload token from the name |
| `env` | `prod`, `dev` or `test`; `shared` on a resource that serves more than one environment |
| `region` | the full region name the resource is deployed to |
| `owner` | a role string, never a person and never a person's address |
| `purpose` | one phrase saying what the resource is for |
| `status` | lifecycle state, such as `active` |
| `repo` | the URL of the repository that governs the resource |

Sources and judgment calls:

- The `region` tag: Microsoft recommends tags that indicate region, and the name-permanence rule
  above is why the region lives here rather than in the name
  (<https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming>).
- `repo` as a URL matches a published functional-tag example verbatim (same source).
- `owner` as a role string is a deliberate deviation from common practice, which prescribes an
  address. The personal-information ban quoted under [No personal tokens](#no-personal-tokens)
  covers tags explicitly. That the ban overrides the practice is judgment, not a sourced claim.
- `env` = `shared` keeps an environment-neutral resource from being tagged with an environment it
  does not belong to, the same reason the environment token appears only where the environment is
  real. Judgment.
- No mandatory tag list is published, so this set is a floor chosen here rather than a standard.
  Judgment.

## Adoption and change

A repository that creates Azure resources links here from its own naming decision record, lists the
names it binds there, and states any deviation there with its reason and revisit trigger. It does
not restate these rules ([reference-dont-duplicate.md](reference-dont-duplicate.md)). A change here
applies to resources created after it and never obliges renaming an existing resource, since most
of these types cannot be renamed.

## Related

- [naming.md](naming.md): the general naming discipline; this file specializes it for Azure
  resource names, where length limits and Microsoft's published abbreviations shape the tokens.
