return {
  cmd = { "yaml-language-server", "--stdio" },
  filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab", "yaml.helm-values" },
  root_markers = { ".git" },
  settings = {
    yaml = {
      format = {
        enable = false,
      },
      schemaStore = {
        enable = true,
      },
      validate = true,
    },
  },
}
