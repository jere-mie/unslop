/* Core transform logic */
const REPLACEMENTS = new Map([
    // Quotes and apostrophes
    ['\u2018', "'"], ['\u2019', "'"], ['\u201A', "'"], ['\u201B', "'"],
    ['\u201C', '"'], ['\u201D', '"'], ['\u201E', '"'], ['\u201F', '"'],
    ['\u2032', "'"], ['\u2033', '"'],
    // Dashes and ellipsis
    ['\u2010', '-'], ['\u2011', '-'], ['\u2012', '-'], ['\u2013', '-'],
    ['\u2014', '-'], ['\u2015', '-'], ['\u2043', '-'], ['\u2212', '-'],
    ['\u2026', '...'],
    // Directional arrows
    ['\u2190', '<-'], ['\u2192', '->'], ['\u2194', '<->'],
    ['\u2191', '^'], ['\u2193', 'v'], ['\u2195', '^v'],
    ['\u21D0', '<='], ['\u21D2', '=>'], ['\u21D4', '<=>'],
    // Bullets, check marks, and list symbols
    ['\u2022', '*'], ['\u2023', '>'], ['\u2610', '[ ]'],
    ['\u2611', '[x]'], ['\u2612', '[x]'], ['\u2713', '[x]'],
    ['\u2714', '[x]'], ['\u2717', '[ ]'], ['\u2718', '[ ]'],
    ['\u2605', '*'], ['\u2606', '*'], ['\u25CF', '*'], ['\u25CB', 'o'],
    // Math and comparison symbols
    ['\u00B1', '+/-'], ['\u00D7', 'x'], ['\u00F7', '/'],
    ['\u2260', '!='], ['\u2264', '<='], ['\u2265', '>='],
    ['\u2248', '~='], ['\u221E', 'inf'],
    // Whitespace and invisible formatting characters
    ['\u00A0', ' '], ['\u2000', ' '], ['\u2001', ' '], ['\u2002', ' '],
    ['\u2003', ' '], ['\u2004', ' '], ['\u2005', ' '], ['\u2006', ' '],
    ['\u2007', ' '], ['\u2008', ' '], ['\u2009', ' '], ['\u200A', ' '],
    ['\u200B', ''], ['\u200C', ''], ['\u200D', ''], ['\u200E', ''],
    ['\u200F', ''], ['\u202F', ' '], ['\u205F', ' '], ['\u2060', ''],
    ['\u3000', ' '], ['\uFEFF', ''],
]);

const TYPE_KEY = {
    '\u201C': 'dquote', '\u201D': 'dquote',
    '\u201E': 'dquote', '\u201F': 'dquote', '\u2033': 'dquote',
    '\u2018': 'squote', '\u2019': 'squote',
    '\u201A': 'squote', '\u201B': 'squote', '\u2032': 'squote',
    '\u2014': 'emdash',
    '\u2013': 'endash',
    '\u2010': 'dash', '\u2011': 'dash', '\u2012': 'dash',
    '\u2015': 'dash', '\u2043': 'dash', '\u2212': 'dash',
    '\u2026': 'ellipsis',
    '\u2190': 'arrow', '\u2192': 'arrow', '\u2194': 'arrow',
    '\u2191': 'arrow', '\u2193': 'arrow', '\u2195': 'arrow',
    '\u21D0': 'arrow', '\u21D2': 'arrow', '\u21D4': 'arrow',
    '\u2022': 'bullet', '\u2023': 'bullet', '\u2605': 'bullet',
    '\u2606': 'bullet', '\u25CF': 'bullet', '\u25CB': 'bullet',
    '\u2610': 'check', '\u2611': 'check', '\u2612': 'check',
    '\u2713': 'check', '\u2714': 'check', '\u2717': 'check', '\u2718': 'check',
    '\u00B1': 'symbol', '\u00D7': 'symbol', '\u00F7': 'symbol',
    '\u2260': 'symbol', '\u2264': 'symbol', '\u2265': 'symbol',
    '\u2248': 'symbol', '\u2212': 'dash', '\u221E': 'symbol',
    '\u00A0': 'nbsp', '\u2000': 'nbsp', '\u2001': 'nbsp', '\u2002': 'nbsp',
    '\u2003': 'nbsp', '\u2004': 'nbsp', '\u2005': 'nbsp', '\u2006': 'nbsp',
    '\u2007': 'nbsp', '\u2008': 'nbsp', '\u2009': 'nbsp', '\u200A': 'nbsp',
    '\u202F': 'nbsp', '\u205F': 'nbsp', '\u3000': 'nbsp',
    '\u200B': 'invisible', '\u200C': 'invisible', '\u200D': 'invisible',
    '\u200E': 'invisible', '\u200F': 'invisible', '\u2060': 'invisible',
    '\uFEFF': 'invisible',
};

function escapeHtml(ch) {
    if (ch === '&') return '&amp;';
    if (ch === '<') return '&lt;';
    if (ch === '>') return '&gt;';
    if (ch === '"') return '&quot;';
    return ch;
}

function processText(rawInput) {
    const cleanParts = [];
    const htmlParts = [];
    let totalCount = 0;
    const typeCounts = {
        dquote: 0, squote: 0, emdash: 0, endash: 0, dash: 0, ellipsis: 0,
        arrow: 0, bullet: 0, check: 0, symbol: 0, nbsp: 0, invisible: 0,
    };

    for (let i = 0; i < rawInput.length; i++) {
        const ch = rawInput[i];

        if (REPLACEMENTS.has(ch)) {
            const replacement = REPLACEMENTS.get(ch);
            const key = TYPE_KEY[ch];
            cleanParts.push(replacement);
            const escapedReplacement = replacement.split('').map(escapeHtml).join('');
            htmlParts.push(`<mark>${escapedReplacement}</mark>`);
            totalCount++;
            typeCounts[key]++;
        } else if (ch === '\n') {
            cleanParts.push('\n');
            htmlParts.push('<br>');
        } else if (ch === '\t') {
            cleanParts.push('\t');
            htmlParts.push('&Tab;');
        } else {
            cleanParts.push(ch);
            htmlParts.push(escapeHtml(ch));
        }
    }

    return {
        cleanText: cleanParts.join(''),
        htmlOutput: htmlParts.join(''),
        totalCount,
        typeCounts,
    };
}

/* ─── DOM refs ─────────────────────────────────────────────────────── */
const inputArea = document.getElementById('input-area');
const outputDiv = document.getElementById('output-display');
const statTotal = document.getElementById('stat-total');
const btnCopy = document.getElementById('btn-copy');
const btnClear = document.getElementById('btn-clear');
const btnUpload = document.getElementById('btn-upload');
const fileInput = document.getElementById('file-input');
const btnDownload = document.getElementById('btn-download');

const typeBadges = {
    dquote: document.getElementById('badge-dquote'),
    squote: document.getElementById('badge-squote'),
    emdash: document.getElementById('badge-emdash'),
    endash: document.getElementById('badge-endash'),
    dash: document.getElementById('badge-dash'),
    ellipsis: document.getElementById('badge-ellipsis'),
    arrow: document.getElementById('badge-arrow'),
    bullet: document.getElementById('badge-bullet'),
    check: document.getElementById('badge-check'),
    symbol: document.getElementById('badge-symbol'),
    nbsp: document.getElementById('badge-nbsp'),
    invisible: document.getElementById('badge-invisible'),
};

let cleanOutput = '';
let prevTotal = 0;
let uploadedFileName = null;

/* ─── Render ───────────────────────────────────────────────────────── */
function render() {
    const raw = inputArea.value;

    if (!raw) {
        outputDiv.innerHTML =
            '<span class="output-empty">Your cleaned text will appear here. Replacements are highlighted in&nbsp;' +
            '<mark style="background:var(--mark-bg);color:var(--accent);border-bottom:1px solid var(--mark-border);padding:0 2px;">green</mark>.</span>';
        statTotal.textContent = '0';
        cleanOutput = '';
        Object.values(typeBadges).forEach(b => b.classList.remove('active'));
        btnDownload.classList.add('disabled');
        return;
    }

    const result = processText(raw);
    cleanOutput = result.cleanText;

    outputDiv.innerHTML = result.htmlOutput;

    // Animate counter if changed
    if (result.totalCount !== prevTotal) {
        statTotal.textContent = result.totalCount;
        statTotal.classList.remove('bump');
        void statTotal.offsetWidth;
        statTotal.classList.add('bump');
        prevTotal = result.totalCount;
    }

    // Update type badges
    for (const [key, badge] of Object.entries(typeBadges)) {
        badge.classList.toggle('active', result.typeCounts[key] > 0);
    }

    // Enable download
    btnDownload.classList.remove('disabled');
}

/* ─── Input events ─────────────────────────────────────────────────── */
inputArea.addEventListener('input', render);

/* ─── Copy output ──────────────────────────────────────────────────── */
btnCopy.addEventListener('click', () => {
    if (!cleanOutput) return;
    const doFeedback = () => {
        btnCopy.textContent = 'Copied!';
        btnCopy.classList.add('copied');
        setTimeout(() => {
            btnCopy.textContent = 'Copy';
            btnCopy.classList.remove('copied');
        }, 1800);
    };
    navigator.clipboard.writeText(cleanOutput).then(doFeedback).catch(() => {
        const ta = document.createElement('textarea');
        ta.value = cleanOutput;
        ta.style.cssText = 'position:fixed;opacity:0;top:0;left:0';
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
        doFeedback();
    });
});

/* ─── Clear ────────────────────────────────────────────────────────── */
btnClear.addEventListener('click', () => {
    inputArea.value = '';
    uploadedFileName = null;
    render();
    inputArea.focus();
});

/* ─── File upload (File API) ───────────────────────────────────────── */
btnUpload.addEventListener('click', () => fileInput.click());

fileInput.addEventListener('change', () => {
    const file = fileInput.files[0];
    if (!file) return;
    uploadedFileName = file.name;

    const reader = new FileReader();
    reader.onload = (e) => {
        inputArea.value = e.target.result;
        render();
        // Reset so the same file can be re-uploaded if needed
        fileInput.value = '';
    };
    reader.onerror = () => {
        alert('Error reading file. Please try again.');
        fileInput.value = '';
    };
    reader.readAsText(file, 'UTF-8');
});

// Also support drag-and-drop onto the input textarea
inputArea.addEventListener('dragover', (e) => {
    e.preventDefault();
    inputArea.style.outline = '2px solid var(--accent)';
});
inputArea.addEventListener('dragleave', () => {
    inputArea.style.outline = '';
});
inputArea.addEventListener('drop', (e) => {
    e.preventDefault();
    inputArea.style.outline = '';
    const file = e.dataTransfer.files[0];
    if (!file) return;
    uploadedFileName = file.name;
    const reader = new FileReader();
    reader.onload = (ev) => {
        inputArea.value = ev.target.result;
        render();
    };
    reader.readAsText(file, 'UTF-8');
});

/* ─── File download (File API / Blob) ─────────────────────────────── */
btnDownload.addEventListener('click', () => {
    if (!cleanOutput || btnDownload.classList.contains('disabled')) return;

    const outName = uploadedFileName
        ? 'unslopped-' + uploadedFileName
        : 'unslopped.txt';

    const blob = new Blob([cleanOutput], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = outName;
    a.style.display = 'none';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    // Revoke after a short delay to let the download begin
    setTimeout(() => URL.revokeObjectURL(url), 10000);
});

/* ─── Install accordion ────────────────────────────────────────────── */
document.querySelectorAll('.install-toggle').forEach(btn => {
    btn.addEventListener('click', () => {
        const targetId = btn.dataset.target;
        const content = document.getElementById(targetId);
        const isOpen = content.classList.contains('open');

        // Close all
        document.querySelectorAll('.install-content.open').forEach(c => c.classList.remove('open'));
        document.querySelectorAll('.install-toggle.open').forEach(b => b.classList.remove('open'));

        // Toggle clicked
        if (!isOpen) {
            content.classList.add('open');
            btn.classList.add('open');
        }
    });
});

/* ─── Copy code blocks ─────────────────────────────────────────────── */
function copyCode(btn) {
    const pre = btn.closest('.code-block-wrap').querySelector('pre.code-block');
    const clone = pre.cloneNode(true);
    clone.querySelectorAll('button').forEach(b => b.remove());
    const text = clone.textContent.trim();

    navigator.clipboard.writeText(text).then(() => {
        btn.textContent = 'Copied!';
        btn.classList.add('copied');
        setTimeout(() => {
            btn.textContent = 'Copy';
            btn.classList.remove('copied');
        }, 1800);
    }).catch(() => {
        btn.textContent = 'Failed';
        setTimeout(() => { btn.textContent = 'Copy'; }, 1800);
    });
}

/* ─── Wrap code blocks so copy button doesn't scroll ────────────────── */
document.querySelectorAll('pre.code-block').forEach(pre => {
    const btn = pre.querySelector('.copy-code-btn');
    if (!btn) return;
    const wrap = document.createElement('div');
    wrap.className = 'code-block-wrap';
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(pre);
    // Move button out of pre into wrapper, before the pre
    wrap.insertBefore(btn, pre);
    // Add top padding to pre so content isn't hidden under the button
    pre.style.paddingTop = '2.5rem';
});

/* ─── Initial render ───────────────────────────────────────────────── */
render();
