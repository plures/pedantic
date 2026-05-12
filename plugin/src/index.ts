import type { RadixPlugin } from '@plures/pares-radix';

const pedantic: RadixPlugin = {
  id: 'pedantic',
  name: 'Pedantic',
  version: '0.1.0',
  icon: '🛡️',
  description: 'DSC v3 compliance and configuration validation with praxis enforcement',

  routes: [
    { path: '/', component: () => import('./pages/ComplianceDashboard.svelte'), title: 'Compliance Dashboard' },
    { path: '/configs', component: () => import('./pages/ConfigBrowser.svelte'), title: 'Config Browser' },
    { path: '/history', component: () => import('./pages/RunHistory.svelte'), title: 'Run History' },
  ],

  navItems: [
    {
      href: '/pedantic',
      label: 'Compliance',
      icon: '🛡️',
      children: [
        { href: '/pedantic', label: 'Dashboard', icon: '🛡️' },
        { href: '/pedantic/configs', label: 'Configs', icon: '📝' },
        { href: '/pedantic/history', label: 'History', icon: '📊' },
      ],
    },
  ],

  settings: [
    {
      key: 'pedantic.auto-validate',
      type: 'toggle',
      label: 'Auto-Validate on Load',
      description: 'Automatically validate configs when they are loaded',
      default: true,
      group: 'Pedantic',
    },
    {
      key: 'pedantic.drift-threshold',
      type: 'number',
      label: 'Drift Threshold (%)',
      description: 'Max drift percentage before generating an alert',
      default: 50,
      group: 'Pedantic',
    },
    {
      key: 'pedantic.demo-mode',
      type: 'toggle',
      label: 'Demo Mode',
      description: 'Use embedded demo data for dashboards and charts',
      default: true,
      group: 'Pedantic',
    },
  ],

  dashboardWidgets: [
    {
      id: 'pedantic-compliance-status',
      title: 'Compliance Status',
      component: () => import('./pages/widgets/ComplianceStatus.svelte'),
      priority: 10,
    },
    {
      id: 'pedantic-recent-runs',
      title: 'Recent Runs',
      component: () => import('./pages/widgets/RecentRuns.svelte'),
      priority: 20,
    },
  ],

  expectations: [
    {
      id: 'compliance-data-fresh',
      domain: 'ux',
      description: 'Warn if no compliance run in the last 24 hours',
      severity: 'warning',
      validate: () => true,
    },
    {
      id: 'config-validated',
      domain: 'business',
      description: 'Error if config is deployed without validation',
      severity: 'error',
      validate: () => true,
    },
  ],
};

export default pedantic;
