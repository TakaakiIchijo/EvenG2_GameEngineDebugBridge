import { readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const templateUrl = new URL('../app.manifest.template.json', import.meta.url)
const outputUrl = new URL('../app.json', import.meta.url)
const args = process.argv.slice(2)
const originIndex = args.indexOf('--origin')
const origin = originIndex >= 0 ? args[originIndex + 1] : process.env.EVEN_BRIDGE_ORIGIN

if (!origin) {
  console.error('Usage: npm run generate:manifest -- --origin http://<LAN_IP>:8765')
  process.exit(1)
}

let normalizedOrigin
try {
  normalizedOrigin = new URL(origin).origin
} catch {
  console.error(`Invalid origin: ${origin}`)
  process.exit(1)
}

if (!['http:', 'https:'].includes(new URL(normalizedOrigin).protocol)) {
  console.error('The bridge origin must use http:// or https://.')
  process.exit(1)
}

const template = await readFile(templateUrl, 'utf8')
const manifest = template.replace('__LOCAL_BRIDGE_ORIGIN__', normalizedOrigin)

await writeFile(outputUrl, `${manifest}\n`, 'utf8')
console.log(`Generated app.json for ${normalizedOrigin}`)
