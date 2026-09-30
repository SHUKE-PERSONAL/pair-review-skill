// Scroll the pair-review browser (launched by split-view.ps1 with a CDP port) to a
// change block and highlight the lines under discussion. Drives the page over CDP,
// so the terminal keeps keyboard focus.
//
//   node focus.mjs change-003 [--at <path>:<ranges>[:old]]... [--reload] [--port 9333]
//   node focus.mjs --open <walkthrough.html>
//
// <path> is the repo-relative file as `diffwalk change` prints it; <ranges> is
// "42" or "42-50,60-62" in that side's line numbers (new side unless ":old").
// The first --at is scrolled to; every --at is highlighted. Without --at, only the
// step is scrolled to.
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { chromium } from 'playwright-core'

const args = process.argv.slice(2)
let change
let port = 9333
let reload = false
let open
const targets = []
for (let i = 0; i < args.length; i++) {
    const a = args[i]
    if (a === '--port') port = Number(args[++i])
    else if (a === '--reload') reload = true
    else if (a === '--open') open = args[++i]
    else if (a === '--at') targets.push(parseAt(args[++i]))
    else change = a
}
if (!change && !open) fail('usage: node focus.mjs change-0NN [--at <path>:<ranges>[:old]]... [--reload] [--port 9333]')

function parseAt(spec) {
    let side = 'new'
    let rest = spec
    if (/:(old|new)$/.test(rest)) {
        side = rest.slice(rest.lastIndexOf(':') + 1)
        rest = rest.slice(0, rest.lastIndexOf(':'))
    }
    const cut = rest.lastIndexOf(':')
    if (cut < 0) fail(`--at needs <path>:<ranges>, got "${spec}"`)
    const ranges = rest.slice(cut + 1).split(',').map((r) => {
        const [s, e] = r.split('-').map(Number)
        if (!Number.isInteger(s)) fail(`bad line range "${r}" in "${spec}"`)
        return [s, Number.isInteger(e) ? e : s]
    })
    return { path: rest.slice(0, cut).split('\\').join('/'), ranges, side }
}

function fail(message) {
    console.error(message)
    process.exit(1)
}

let browser
try {
    browser = await chromium.connectOverCDP(`http://127.0.0.1:${port}`)
} catch {
    fail(`no pair-review browser on CDP port ${port} — open it with split-view.ps1 first`)
}
const pages = browser.contexts().flatMap((c) => c.pages())
const page = pages.find((p) => p.url().startsWith('file:')) ?? (open ? pages[0] : undefined)
if (!page) fail('pair-review browser has no walkthrough tab open')
if (open) {
    await page.goto(pathToFileURL(resolve(open)).href)
    await page.bringToFront()
} else if (reload) await page.reload()
await page.waitForFunction(() => document.querySelector('[data-diff-mount]') !== null)
if (!change) {
    await browser.close()
    console.log(`opened ${page.url()}`)
    process.exit(0)
}

const result = await page.evaluate(async ({ change, targets }) => {
    const anchor = document.getElementById(change)
    if (!anchor) return { error: `${change} not found (only a change's canonical step carries its anchor)` }
    const step = anchor.closest('.step')
    const fold = step.closest('details.section-fold')
    if (fold) fold.open = true

    for (const root of document.querySelectorAll('diffs-container')) {
        for (const el of root.shadowRoot?.querySelectorAll('[data-pr-hl]') ?? []) el.removeAttribute('data-pr-hl')
    }

    const report = []
    let first = null
    for (const t of targets) {
        const file = [...step.querySelectorAll('details.file')].find((d) =>
            d.querySelector('summary').textContent.split(' ').some((word) => word === t.path),
        )
        if (!file) {
            report.push(`${t.path}: not in this step`)
            continue
        }
        file.open = true
        let root
        for (let i = 0; i < 50 && !root?.querySelector('[data-line]'); i++) {
            await new Promise((r) => setTimeout(r, 100))
            root = file.querySelector('diffs-container')?.shadowRoot
        }
        if (!root?.querySelector('[data-line]')) {
            report.push(`${t.path}: diff did not render`)
            continue
        }
        if (!root.querySelector('style[data-pr-hl-style]')) {
            const style = document.createElement('style')
            style.setAttribute('data-pr-hl-style', '')
            style.textContent = `[data-pr-hl] {
  background-image: linear-gradient(rgba(250, 204, 21, 0.35), rgba(250, 204, 21, 0.35)) !important;
  box-shadow: inset 3px 0 0 #d97706;
}`
            root.appendChild(style)
        }

        const split = root.querySelector('pre')?.getAttribute('data-diff-type') === 'split'
        const column = split
            ? root.querySelector(t.side === 'old' ? 'code[data-deletions]' : 'code[data-additions]')
            : root.querySelector('code[data-code]')
        const inRange = (n) => t.ranges.some(([s, e]) => n >= s && n <= e)
        const lineOf = (row) => {
            if (split) return Number(row.dataset.line)
            const deletion = row.dataset.lineType === 'change-deletion'
            if (t.side === 'old') return Number(deletion ? row.dataset.line : row.dataset.altLine)
            return deletion ? NaN : Number(row.dataset.line)
        }
        const indexes = new Set(
            [...(column?.querySelectorAll('[data-line][data-line-index]') ?? [])]
                .filter((row) => inRange(lineOf(row)))
                .map((row) => row.dataset.lineIndex),
        )
        const hits = [...column.querySelectorAll('[data-line-index]')].filter((el) => indexes.has(el.dataset.lineIndex))
        for (const el of hits) el.setAttribute('data-pr-hl', '')
        report.push(`${t.path}: ${indexes.size} ${t.side} line(s) highlighted`)
        first ??= hits.find((el) => el.hasAttribute('data-line')) ?? file
    }

    ;(first ?? step).scrollIntoView({ block: first ? 'center' : 'start' })
    return { report }
}, { change, targets })

await browser.close()
if (result.error) fail(result.error)
console.log([`focused ${change}`, ...result.report].join('\n'))
