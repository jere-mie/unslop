/* ─── Core transform logic ─────────────────────────────────────────── */
const REPLACEMENTS = new Map([
    ['\u201C', '"'],   // left double quote   "
    ['\u201D', '"'],   // right double quote  "
    ['\u2018', "'"],   // left single quote   '
    ['\u2019', "'"],   // right single quote  '
    ['\u2014', '-'],   // em dash             —
    ['\u2013', '-'],   // en dash             –
    ['\u2026', '...'], // ellipsis            …
    ['\u00A0', ' '],   // non-breaking space
]);

const TYPE_KEY = {
    '\u201C': 'dquote', '\u201D': 'dquote',
    '\u2018': 'squote', '\u2019': 'squote',
    '\u2014': 'emdash',
    '\u2013': 'endash',
    '\u2026': 'ellipsis',
    '\u00A0': 'nbsp',
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
    const typeCounts = { dquote: 0, squote: 0, emdash: 0, endash: 0, ellipsis: 0, nbsp: 0 };

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
    ellipsis: document.getElementById('badge-ellipsis'),
    nbsp: document.getElementById('badge-nbsp'),
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
