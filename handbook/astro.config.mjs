// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Local preview (`just handbook`) is the site root. GitHub Pages serves the
// handbook under /docs/ — set HANDBOOK_BASE=/docs for that build.
const handbookBase = process.env.HANDBOOK_BASE || '/';

export default defineConfig({
  site: 'https://openpocketcine.app',
  base: handbookBase,
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'OpenPocketCine',
      description:
        'OpenPocketCine docs: protocol, iOS and Android apps, and how to build.',
      logo: {
        src: './src/assets/icon.png',
        alt: 'OpenPocketCine',
      },
      favicon: 'favicon.png',
      defaultLocale: 'root',
      locales: {
        root: { label: 'English', lang: 'en' },
        'zh-tw': { label: '繁體中文', lang: 'zh-TW' },
      },
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/erik-sutton95/OpenPocketCine',
        },
      ],
      sidebar: [
        {
          label: 'Start', translations: { 'zh-TW': '開始' },
          items: [
            { label: 'Overview', translations: { 'zh-TW': '總覽' }, slug: '' },
            { label: 'Open beta 102 notes', translations: { 'zh-TW': '公開測試 102 版說明' }, slug: 'releases/beta-102' },
            { label: 'Setup and build', translations: { 'zh-TW': '安裝與建置' }, slug: 'guides/setup' },
            { label: 'Troubleshooting', translations: { 'zh-TW': '疑難排解' }, slug: 'guides/troubleshooting' },
            { label: 'Multiview prototype', translations: { 'zh-TW': '多機畫面原型' }, slug: 'guides/multiview-prototype' },
            { label: 'Keeping docs current', translations: { 'zh-TW': '文件維護' }, slug: 'contribute/documentation' },
          ],
        },
        {
          label: 'Apps', translations: { 'zh-TW': '應用程式' },
          items: [
            { label: 'Architecture', translations: { 'zh-TW': '架構' }, slug: 'apps/architecture' },
            { label: 'iOS', translations: { 'zh-TW': 'iOS 版' }, slug: 'apps/ios' },
            { label: 'Android', translations: { 'zh-TW': 'Android 版' }, slug: 'apps/android' },
          ],
        },
        {
          label: 'Protocol', translations: { 'zh-TW': '通訊協定' },
          items: [
            { label: 'Connection spine', translations: { 'zh-TW': '連線主流程' }, slug: 'protocol/connection' },
            { label: 'BLE pairing', translations: { 'zh-TW': '藍牙配對' }, slug: 'protocol/ble' },
            { label: 'Camera Wi-Fi', translations: { 'zh-TW': '相機 Wi-Fi' }, slug: 'protocol/wifi' },
            { label: 'DUML frame', translations: { 'zh-TW': 'DUML 封包格式' }, slug: 'protocol/duml-frame' },
            { label: 'DUML transport', translations: { 'zh-TW': 'DUML 傳輸層' }, slug: 'protocol/duml-transport' },
            { label: 'Command catalog', translations: { 'zh-TW': '指令清單' }, slug: 'protocol/commands' },
            { label: 'Pocket 3 findings', translations: { 'zh-TW': 'Pocket 3 實測發現' }, slug: 'protocol/pocket3' },
            { label: 'Pocket 4 Pro modes', translations: { 'zh-TW': 'Pocket 4 Pro 模式' }, slug: 'protocol/pocket4-pro' },
            { label: 'Live view', translations: { 'zh-TW': '即時畫面' }, slug: 'protocol/live-view' },
            { label: 'HTTP media', translations: { 'zh-TW': 'HTTP 媒體' }, slug: 'protocol/media' },
            { label: 'iOS notes', translations: { 'zh-TW': 'iOS 筆記' }, slug: 'protocol/ios' },
          ],
        },
      ],
    }),
  ],
});
