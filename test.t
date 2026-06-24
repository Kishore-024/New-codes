version: "3.9"

services:
  mcp-inspector:
    image: node:20-alpine
    container_name: mcp-inspector
    working_dir: /app
    command: >
      sh -c "
      npm install -g @modelcontextprotocol/inspector &&
      npx @modelcontextprotocol/inspector
      "
    ports:
      - "6274:6274"
      - "6277:6277"
    stdin_open: true
    tty: true
