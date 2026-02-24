import * as vscode from 'vscode';
import * as net from 'net';
import * as fs from 'fs';
import * as path from 'path';

let statusBarItem: vscode.StatusBarItem;
let diagnostics: vscode.DiagnosticCollection;

const themeColorVar = 'var(--vscode-editor-wordHighlightBackground)';
const flashSteps = [
    vscode.window.createTextEditorDecorationType({
        backgroundColor: new vscode.ThemeColor('editor.wordHighlightBackground'),
    }),
    vscode.window.createTextEditorDecorationType({
        backgroundColor: `color-mix(in srgb, ${themeColorVar} 50%, transparent)`,
    }),
    vscode.window.createTextEditorDecorationType({
        backgroundColor: `color-mix(in srgb, ${themeColorVar} 15%, transparent)`,
    }),
];
const FLASH_STEP_MS = [220, 150, 130]; // ~500ms total
let flashTimeout: ReturnType<typeof setTimeout> | undefined;

function flashRange(editor: vscode.TextEditor, range: vscode.Range) {
    if (flashTimeout) { clearTimeout(flashTimeout); }
    for (const d of flashSteps) { editor.setDecorations(d, []); }

    let step = 0;
    const advance = () => {
        if (step > 0) {
            editor.setDecorations(flashSteps[step - 1], []);
        }
        if (step < flashSteps.length) {
            editor.setDecorations(flashSteps[step], [range]);
            flashTimeout = setTimeout(advance, FLASH_STEP_MS[step]);
            step++;
        }
    };
    advance();
}

export function activate(context: vscode.ExtensionContext) {
    statusBarItem = vscode.window.createStatusBarItem(
        vscode.StatusBarAlignment.Left, 0
    );
    context.subscriptions.push(statusBarItem);

    diagnostics = vscode.languages.createDiagnosticCollection('fy');
    context.subscriptions.push(diagnostics);

    // Clear diagnostics when the user edits the file
    context.subscriptions.push(
        vscode.workspace.onDidChangeTextDocument(e => {
            if (e.document.languageId === 'fy' && e.contentChanges.length > 0) {
                diagnostics.delete(e.document.uri);
            }
        })
    );

    context.subscriptions.push(
        vscode.commands.registerCommand('fy.evalDefinition', evalDefinition)
    );
}

export function deactivate() {}

/**
 * Find the word definition surrounding the cursor.
 * Scans backward for `: `, `:: `, or `macro: ` then forward for the matching `;`.
 */
interface DefinitionResult {
    text: string;
    range: vscode.Range;
}

function findDefinitionAtCursor(
    document: vscode.TextDocument,
    position: vscode.Position
): DefinitionResult | null {
    const text = document.getText();
    const offset = document.offsetAt(position);

    // Find all definition starts and pick the nearest one before the cursor
    const defPatterns = [/(?:^|\n)(:\s)/g, /(?:^|\n)(::\s)/g, /(?:^|\n)(macro:\s)/g];

    let bestStart = -1;

    for (const pattern of defPatterns) {
        let match;
        while ((match = pattern.exec(text)) !== null) {
            const defStart = match.index + (match[0].length - match[1].length);
            if (defStart <= offset && defStart > bestStart) {
                bestStart = defStart;
            }
        }
    }

    if (bestStart === -1) {
        return null;
    }

    // Find the matching `;` — in FY, `;` always ends a definition (quotes use `]`)
    // Skip `;` inside string literals
    let i = bestStart;
    let inString = false;
    while (i < text.length) {
        if (text[i] === '"' && (i === 0 || text[i - 1] !== '\\')) {
            inString = !inString;
        }
        if (!inString && text[i] === ';') {
            if (i + 1 >= text.length || /\s/.test(text[i + 1])) {
                const defEnd = i + 1;
                if (offset <= defEnd) {
                    return {
                        text: text.substring(bestStart, defEnd),
                        range: new vscode.Range(
                            document.positionAt(bestStart),
                            document.positionAt(defEnd)
                        ),
                    };
                }
                break; // cursor is past this definition
            }
        }
        i++;
    }

    return null;
}

/**
 * Read .fy-port from the workspace root or the directory of the current file.
 */
function readPort(documentUri: vscode.Uri): number | null {
    // Try workspace root first
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (workspaceFolders) {
        for (const folder of workspaceFolders) {
            const portFile = path.join(folder.uri.fsPath, '.fy-port');
            try {
                const port = parseInt(fs.readFileSync(portFile, 'utf8').trim(), 10);
                if (!isNaN(port)) { return port; }
            } catch { /* try next */ }
        }
    }
    // Try directory of current file
    const dir = path.dirname(documentUri.fsPath);
    try {
        const port = parseInt(fs.readFileSync(path.join(dir, '.fy-port'), 'utf8').trim(), 10);
        if (!isNaN(port)) { return port; }
    } catch { /* not found */ }
    return null;
}

/**
 * Send code to the running FY process via TCP.
 */
function sendToFy(port: number, filePath: string, code: string): Promise<string> {
    return new Promise((resolve, reject) => {
        const client = new net.Socket();
        let response = '';

        client.connect(port, '127.0.0.1', () => {
            client.write(filePath + '\n' + code);
            client.end();
        });

        client.on('data', (data) => { response += data.toString(); });
        client.on('end', () => { resolve(response.trim()); });
        client.on('error', (err) => { reject(err); });
        client.setTimeout(5000, () => {
            client.destroy();
            reject(new Error('Connection timed out'));
        });
    });
}

async function evalDefinition() {
    const editor = vscode.window.activeTextEditor;
    if (!editor || editor.document.languageId !== 'fy') {
        vscode.window.showWarningMessage('No active .fy file');
        return;
    }

    const result = findDefinitionAtCursor(editor.document, editor.selection.active);
    if (!result) {
        vscode.window.showWarningMessage('No word definition found at cursor');
        return;
    }

    const port = readPort(editor.document.uri);
    if (port === null) {
        vscode.window.showErrorMessage('No .fy-port found. Run your program with: fy --serve file.fy');
        return;
    }

    // Flash highlight the definition being sent
    flashRange(editor, result.range);

    const filePath = editor.document.uri.fsPath;
    statusBarItem.text = '$(sync~spin) fy: sending...';
    statusBarItem.show();

    try {
        const response = await sendToFy(port, filePath, result.text);
        if (response.startsWith('ok')) {
            diagnostics.delete(editor.document.uri);
            const nameMatch = result.text.match(/^(?::|::|macro:)\s+(\S+)/);
            const wordName = nameMatch ? nameMatch[1] : 'definition';
            statusBarItem.text = `$(check) fy: ${wordName}`;
            vscode.window.setStatusBarMessage(`fy: ${wordName} updated`, 3000);
        } else {
            // Parse structured error: "error:{line}:{message}"
            const errMatch = response.match(/^error:(\d+):(.+)/);
            if (errMatch) {
                const errLine = parseInt(errMatch[1], 10);
                const errMsg = errMatch[2];
                // errLine is relative to the sent code; map to document position
                const docLine = Math.min(
                    result.range.start.line + errLine - 1,
                    editor.document.lineCount - 1
                );
                const lineText = editor.document.lineAt(docLine).text;
                const diagRange = new vscode.Range(docLine, 0, docLine, lineText.length);
                const diag = new vscode.Diagnostic(diagRange, errMsg, vscode.DiagnosticSeverity.Error);
                diag.source = 'fy';
                diagnostics.set(editor.document.uri, [diag]);
                statusBarItem.text = `$(error) fy: ${errMsg}`;
            } else {
                // Legacy format or unexpected response
                statusBarItem.text = '$(error) fy: error';
                vscode.window.showErrorMessage(`fy: ${response}`);
            }
        }
    } catch (err: any) {
        statusBarItem.text = '$(error) fy: disconnected';
        vscode.window.showErrorMessage(`fy: could not connect — ${err.message}`);
    }

    setTimeout(() => statusBarItem.hide(), 3000);
}
