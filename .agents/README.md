# Contexto compartilhado com o Claude

[AGENTS.md](../AGENTS.md) aponta para [CLAUDE.md](../CLAUDE.md): ambos usam as
mesmas regras e o mesmo índice de documentação, sem cópia do conteúdo.

- [Documentação do projeto](../docs/), começando pelo [CODEMAP](../docs/CODEMAP.md).
- [Memória do Claude para o Getman](claude-memory/MEMORY.md): consulte o índice e
  leia os arquivos relevantes à tarefa. São notas históricas; confira o código
  atual antes de assumir que continuam válidas.
- [Plugins habilitados do Claude](claude-plugins/): fontes completas, incluindo
  documentação, referências, comandos e definições de agentes.
- [Skills](skills/): links para as pastas completas, incluindo scripts e assets.

Os links em `.agents/` são locais desta máquina e apontam para a instalação
atual do Claude. Alterações nos arquivos de origem aparecem imediatamente.
Se uma atualização do Claude mudar a pasta versionada de um plugin, recrie
os links correspondentes usando `~/.claude/plugins/installed_plugins.json`.
Não foram incluídas skills da lixeira nem cópias internas alternativas dos plugins.

O prefixo `claude-` identifica a origem das pastas; o campo `name` dos manifests
originais foi preservado. Skills homônimas já instaladas no Codex podem aparecer
mais de uma vez. Estes links compartilham arquivos; não instalam MCPs, hooks,
LSPs ou ferramentas específicas do Claude. Use apenas ferramentas disponíveis
na sessão e respeite as instruções do projeto e do usuário.

Fontes oficiais: [descoberta de skills e suporte a symlinks](https://learn.chatgpt.com/docs/build-skills)
e [instruções AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

## Inventário das skills vinculadas

| Link | Origem |
| --- | --- |
| [claude-microgw-integration](skills/claude-microgw-integration/SKILL.md) | `/Users/thiago/.claude/skills/microgw-integration` |
| [claude-ordens-de-servico](skills/claude-ordens-de-servico/SKILL.md) | `/Users/thiago/.claude/skills/ordens-de-servico` |
| [claude-docx](skills/claude-docx/SKILL.md) | `/Users/thiago/.claude/skills/synced/a02dbcfe-d68a-41d7-bdbb-214c4661150d_2d495f76-a519-4e45-ad2c-2a1982afa473/docx` |
| [claude-google-workspace](skills/claude-google-workspace/SKILL.md) | `/Users/thiago/.claude/skills/synced/a02dbcfe-d68a-41d7-bdbb-214c4661150d_2d495f76-a519-4e45-ad2c-2a1982afa473/google-workspace` |
| [claude-import-memory](skills/claude-import-memory/SKILL.md) | `/Users/thiago/.claude/skills/synced/a02dbcfe-d68a-41d7-bdbb-214c4661150d_2d495f76-a519-4e45-ad2c-2a1982afa473/import-memory` |
| [claude-morning](skills/claude-morning/SKILL.md) | `/Users/thiago/.claude/skills/synced/a02dbcfe-d68a-41d7-bdbb-214c4661150d_2d495f76-a519-4e45-ad2c-2a1982afa473/morning` |
| [claude-pdf](skills/claude-pdf/SKILL.md) | `/Users/thiago/.claude/skills/synced/a02dbcfe-d68a-41d7-bdbb-214c4661150d_2d495f76-a519-4e45-ad2c-2a1982afa473/pdf` |
| [claude-pptx](skills/claude-pptx/SKILL.md) | `/Users/thiago/.claude/skills/synced/a02dbcfe-d68a-41d7-bdbb-214c4661150d_2d495f76-a519-4e45-ad2c-2a1982afa473/pptx` |
| [claude-skill-creator](skills/claude-skill-creator/SKILL.md) | `/Users/thiago/.claude/skills/synced/a02dbcfe-d68a-41d7-bdbb-214c4661150d_2d495f76-a519-4e45-ad2c-2a1982afa473/skill-creator` |
| [claude-xlsx](skills/claude-xlsx/SKILL.md) | `/Users/thiago/.claude/skills/synced/a02dbcfe-d68a-41d7-bdbb-214c4661150d_2d495f76-a519-4e45-ad2c-2a1982afa473/xlsx` |
| [claude-careca-boot-careca-boot](skills/claude-careca-boot-careca-boot/SKILL.md) | `/Users/thiago/.claude/plugins/cache/ddmx/careca-boot/ab69cc34b628/skills/careca-boot` |
| [claude-claude-code-setup-claude-automation-recommender](skills/claude-claude-code-setup-claude-automation-recommender/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/claude-code-setup/1.0.0/skills/claude-automation-recommender` |
| [claude-claude-md-management-claude-md-improver](skills/claude-claude-md-management-claude-md-improver/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/claude-md-management/1.0.0/skills/claude-md-improver` |
| [claude-frontend-design-frontend-design](skills/claude-frontend-design-frontend-design/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/frontend-design/f359d43b4060/skills/frontend-design` |
| [claude-mongodb-mongodb-atlas-stream-processing](skills/claude-mongodb-mongodb-atlas-stream-processing/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/mongodb/1.2.1/skills/mongodb-atlas-stream-processing` |
| [claude-mongodb-mongodb-connection](skills/claude-mongodb-mongodb-connection/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/mongodb/1.2.1/skills/mongodb-connection` |
| [claude-mongodb-mongodb-mcp-setup](skills/claude-mongodb-mongodb-mcp-setup/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/mongodb/1.2.1/skills/mongodb-mcp-setup` |
| [claude-mongodb-mongodb-natural-language-querying](skills/claude-mongodb-mongodb-natural-language-querying/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/mongodb/1.2.1/skills/mongodb-natural-language-querying` |
| [claude-mongodb-mongodb-query-optimizer](skills/claude-mongodb-mongodb-query-optimizer/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/mongodb/1.2.1/skills/mongodb-query-optimizer` |
| [claude-mongodb-mongodb-schema-design](skills/claude-mongodb-mongodb-schema-design/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/mongodb/1.2.1/skills/mongodb-schema-design` |
| [claude-mongodb-mongodb-search-and-ai](skills/claude-mongodb-mongodb-search-and-ai/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/mongodb/1.2.1/skills/mongodb-search-and-ai` |
| [claude-skill-creator-skill-creator](skills/claude-skill-creator-skill-creator/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/skill-creator/f359d43b4060/skills/skill-creator` |
| [claude-superpowers-brainstorming](skills/claude-superpowers-brainstorming/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/brainstorming` |
| [claude-superpowers-diagnosing-superpowers](skills/claude-superpowers-diagnosing-superpowers/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/diagnosing-superpowers` |
| [claude-superpowers-dispatching-parallel-agents](skills/claude-superpowers-dispatching-parallel-agents/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/dispatching-parallel-agents` |
| [claude-superpowers-executing-plans](skills/claude-superpowers-executing-plans/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/executing-plans` |
| [claude-superpowers-finishing-a-development-branch](skills/claude-superpowers-finishing-a-development-branch/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/finishing-a-development-branch` |
| [claude-superpowers-receiving-code-review](skills/claude-superpowers-receiving-code-review/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/receiving-code-review` |
| [claude-superpowers-requesting-code-review](skills/claude-superpowers-requesting-code-review/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/requesting-code-review` |
| [claude-superpowers-subagent-driven-development](skills/claude-superpowers-subagent-driven-development/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/subagent-driven-development` |
| [claude-superpowers-systematic-debugging](skills/claude-superpowers-systematic-debugging/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/systematic-debugging` |
| [claude-superpowers-test-driven-development](skills/claude-superpowers-test-driven-development/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/test-driven-development` |
| [claude-superpowers-using-git-worktrees](skills/claude-superpowers-using-git-worktrees/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/using-git-worktrees` |
| [claude-superpowers-using-superpowers](skills/claude-superpowers-using-superpowers/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/using-superpowers` |
| [claude-superpowers-verification-before-completion](skills/claude-superpowers-verification-before-completion/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/verification-before-completion` |
| [claude-superpowers-writing-plans](skills/claude-superpowers-writing-plans/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/writing-plans` |
| [claude-superpowers-writing-skills](skills/claude-superpowers-writing-skills/SKILL.md) | `/Users/thiago/.claude/plugins/cache/claude-plugins-official/superpowers/6.4.1/skills/writing-skills` |
