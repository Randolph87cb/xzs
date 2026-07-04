const { spawnSync } = require('child_process')
const path = require('path')

const root = path.resolve(__dirname, '..')
const result = spawnSync('pnpm', ['--dir', path.join(root, 'frontend'), '--filter', '@xzs/question-renderer', 'test'], {
  stdio: 'inherit',
  shell: process.platform === 'win32'
})

if (result.error) {
  console.error(result.error.message)
  process.exit(1)
}

process.exit(result.status || 0)
