"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.InventoryDetailPanel = void 0;
const vscode = __importStar(require("vscode"));
const inventoryTreeProvider_1 = require("./inventoryTreeProvider");
class InventoryDetailPanel {
    static instance;
    panel;
    disposables = [];
    context;
    logs = [];
    tasks = new Map();
    static createOrShow(context) {
        if (InventoryDetailPanel.instance) {
            InventoryDetailPanel.instance.panel.reveal();
            return InventoryDetailPanel.instance;
        }
        const panel = vscode.window.createWebviewPanel('pedanticInventoryDetail', 'Inventory Details', vscode.ViewColumn.Two, {
            enableScripts: true,
            retainContextWhenHidden: true
        });
        InventoryDetailPanel.instance = new InventoryDetailPanel(panel, context);
        return InventoryDetailPanel.instance;
    }
    static current() {
        return InventoryDetailPanel.instance;
    }
    constructor(panel, context) {
        this.panel = panel;
        this.context = context;
        this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
        this.panel.webview.html = this.getHtml();
        // Load persisted logs from globalState
        this.loadLogs();
        // Handle messages from webview
        this.panel.webview.onDidReceiveMessage(message => {
            switch (message.command) {
                case 'pushConfig':
                    this.handlePushConfig(message.hostName, message.configPath);
                    break;
            }
        }, null, this.disposables);
    }
    showItemDetails(item) {
        const details = this.formatItemDetails(item);
        this.panel.webview.postMessage({ command: 'showDetails', details });
    }
    addLog(log) {
        this.logs.push(log);
        // Keep only last 1000 logs
        if (this.logs.length > 1000) {
            this.logs = this.logs.slice(-1000);
        }
        this.saveLogs();
        this.updateLogs();
    }
    updateTaskProgress(task) {
        this.tasks.set(task.hostName, task);
        this.panel.webview.postMessage({ command: 'updateTask', task });
    }
    /**
     * Start a configuration push operation
     */
    startConfigPush(hostName, configPath) {
        this.handlePushConfig(hostName, configPath);
    }
    formatItemDetails(item) {
        const details = {
            title: item.label,
            type: item.itemType,
            content: {}
        };
        switch (item.itemType) {
            case inventoryTreeProvider_1.InventoryItemType.Host:
                const host = item.data;
                details.content = {
                    name: host.name,
                    groups: host.groups,
                    varsCount: Object.keys(host.vars || {}).length,
                    factsCount: Object.keys(host.facts || {}).length
                };
                details.actions = [
                    { id: 'pushConfig', label: 'Push Configuration', hostName: host.name }
                ];
                break;
            case inventoryTreeProvider_1.InventoryItemType.HostVars:
            case inventoryTreeProvider_1.InventoryItemType.HostGroupVars:
                details.content = item.data.vars || {};
                break;
            case inventoryTreeProvider_1.InventoryItemType.HostFacts:
                details.content = item.data.facts || {};
                break;
            case inventoryTreeProvider_1.InventoryItemType.VarItem:
            case inventoryTreeProvider_1.InventoryItemType.FactItem:
                details.content = {
                    key: item.data.key,
                    value: item.data.value,
                    type: typeof item.data.value
                };
                break;
        }
        return details;
    }
    updateLogs() {
        const logsToSend = this.logs.slice(-100); // Send last 100 logs
        this.panel.webview.postMessage({ command: 'updateLogs', logs: logsToSend });
    }
    async loadLogs() {
        const savedLogs = this.context.globalState.get('pedantic.inventory.logs', []);
        this.logs = savedLogs;
        this.updateLogs();
    }
    async saveLogs() {
        await this.context.globalState.update('pedantic.inventory.logs', this.logs);
    }
    async handlePushConfig(hostName, configPath) {
        // Create a task
        const task = {
            hostName,
            configPath: configPath || '',
            status: 'pending',
            progress: 0,
            startTime: new Date()
        };
        this.updateTaskProgress(task);
        // Simulate config push (would integrate with PowerShell bridge in real implementation)
        task.status = 'running';
        this.updateTaskProgress(task);
        this.addLog({
            hostName,
            timestamp: new Date(),
            level: 'info',
            message: `Starting configuration push to ${hostName}`
        });
        // Simulate progress
        for (let i = 0; i <= 100; i += 10) {
            await new Promise(resolve => globalThis.setTimeout(resolve, 200));
            task.progress = i;
            this.updateTaskProgress(task);
        }
        task.status = 'success';
        task.endTime = new Date();
        this.updateTaskProgress(task);
        this.addLog({
            hostName,
            timestamp: new Date(),
            level: 'success',
            message: `Configuration successfully pushed to ${hostName}`
        });
    }
    dispose() {
        while (this.disposables.length) {
            const x = this.disposables.pop();
            if (x) {
                x.dispose();
            }
        }
        InventoryDetailPanel.instance = undefined;
    }
    getHtml() {
        const nonce = Math.random().toString(36).slice(2);
        return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Inventory Details</title>
<style>
body { 
  font-family: var(--vscode-font-family, Segoe UI, Arial, sans-serif); 
  margin: 0; 
  padding: 1rem; 
  color: var(--vscode-foreground);
}
.section { 
  border: 1px solid var(--vscode-editorWidget-border, #555); 
  padding: 0.75rem; 
  border-radius: 6px; 
  margin-bottom: 0.75rem; 
  background: var(--vscode-editor-background, #1e1e1e); 
}
.section h3 { margin-top: 0; font-size: 1rem; }
.detail-content { 
  font-family: var(--vscode-editor-font-family, 'Courier New', monospace);
  font-size: 0.9rem;
  white-space: pre-wrap;
  overflow-x: auto;
}
.actions { margin-top: 0.5rem; }
.action-btn {
  background: var(--vscode-button-background);
  color: var(--vscode-button-foreground);
  border: none;
  padding: 6px 12px;
  border-radius: 4px;
  cursor: pointer;
  margin-right: 8px;
}
.action-btn:hover {
  background: var(--vscode-button-hoverBackground);
}
.log-entry {
  padding: 4px 8px;
  border-left: 3px solid #666;
  margin-bottom: 4px;
  font-size: 0.85rem;
}
.log-entry.info { border-left-color: #0078d4; }
.log-entry.success { border-left-color: #74c69d; }
.log-entry.warning { border-left-color: #ffb000; }
.log-entry.error { border-left-color: #ff6b6b; }
.log-time { color: var(--vscode-descriptionForeground, #999); font-size: 0.8rem; }
.progress-bar {
  width: 100%;
  height: 20px;
  background: var(--vscode-editorWidget-background, #252526);
  border-radius: 4px;
  overflow: hidden;
  margin: 8px 0;
}
.progress-fill {
  height: 100%;
  background: var(--vscode-progressBar-background, #0078d4);
  transition: width 0.3s ease;
}
.task-status {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 3px;
  font-size: 0.8rem;
  margin-left: 8px;
}
.task-status.pending { background: #666; }
.task-status.running { background: #0078d4; }
.task-status.success { background: #74c69d; }
.task-status.failed { background: #ff6b6b; }
</style>
</head>
<body>
<div class="section" id="details-section">
  <h3>Details</h3>
  <div id="details-content" class="detail-content">Select an item from the inventory tree to view details</div>
  <div id="actions-content" class="actions"></div>
</div>

<div class="section" id="tasks-section" style="display: none;">
  <h3>Configuration Tasks</h3>
  <div id="tasks-content"></div>
</div>

<div class="section" id="logs-section">
  <h3>Host Logs</h3>
  <div id="logs-content" style="max-height: 300px; overflow-y: auto;">No logs yet</div>
</div>

<script nonce="${nonce}">
(function() {
  const vscode = acquireVsCodeApi();
  const detailsContent = document.getElementById('details-content');
  const actionsContent = document.getElementById('actions-content');
  const tasksContent = document.getElementById('tasks-content');
  const tasksSection = document.getElementById('tasks-section');
  const logsContent = document.getElementById('logs-content');

  // HTML escape function to prevent XSS
  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  window.addEventListener('message', event => {
    const message = event.data;
    
    switch (message.command) {
      case 'showDetails':
        renderDetails(message.details);
        break;
      case 'updateTask':
        renderTask(message.task);
        break;
      case 'updateLogs':
        renderLogs(message.logs);
        break;
    }
  });

  function renderDetails(details) {
    detailsContent.textContent = details.title + '\\n' +
      'Type: ' + details.type + '\\n\\n' +
      JSON.stringify(details.content, null, 2);
    
    // Render actions using createElement for safety
    if (details.actions && details.actions.length > 0) {
      actionsContent.innerHTML = '';
      details.actions.forEach(action => {
        const btn = document.createElement('button');
        btn.className = 'action-btn';
        btn.textContent = action.label;
        btn.addEventListener('click', () => {
          vscode.postMessage({ command: action.id, hostName: action.hostName || '' });
        });
        actionsContent.appendChild(btn);
      });
    } else {
      actionsContent.innerHTML = '';
    }
  }

  function renderTask(task) {
    tasksSection.style.display = 'block';
    const statusClass = task.status;
    const taskDiv = document.createElement('div');
    taskDiv.className = 'task-item';
    
    const hostLabel = document.createElement('strong');
    hostLabel.textContent = task.hostName;
    taskDiv.appendChild(hostLabel);
    
    const statusSpan = document.createElement('span');
    statusSpan.className = 'task-status ' + statusClass;
    statusSpan.textContent = task.status;
    taskDiv.appendChild(statusSpan);
    
    const progressBar = document.createElement('div');
    progressBar.className = 'progress-bar';
    const progressFill = document.createElement('div');
    progressFill.className = 'progress-fill';
    progressFill.style.width = task.progress + '%';
    progressBar.appendChild(progressFill);
    taskDiv.appendChild(progressBar);
    
    if (task.error) {
      const errorDiv = document.createElement('div');
      errorDiv.style.color = '#ff6b6b';
      errorDiv.textContent = task.error;
      taskDiv.appendChild(errorDiv);
    }
    
    tasksContent.innerHTML = '';
    tasksContent.appendChild(taskDiv);
  }

  function renderLogs(logs) {
    if (!logs || logs.length === 0) {
      logsContent.textContent = 'No logs yet';
      return;
    }
    
    logsContent.innerHTML = '';
    logs.forEach(log => {
      const logDiv = document.createElement('div');
      logDiv.className = 'log-entry ' + log.level;
      
      const time = new Date(log.timestamp).toLocaleTimeString();
      const timeSpan = document.createElement('span');
      timeSpan.className = 'log-time';
      timeSpan.textContent = '[' + time + '] ';
      logDiv.appendChild(timeSpan);
      
      const hostLabel = document.createElement('strong');
      hostLabel.textContent = log.hostName;
      logDiv.appendChild(hostLabel);
      
      logDiv.appendChild(document.createTextNode(': ' + log.message));
      logsContent.appendChild(logDiv);
    });
  }
})();
</script>
</body>
</html>`;
    }
}
exports.InventoryDetailPanel = InventoryDetailPanel;
