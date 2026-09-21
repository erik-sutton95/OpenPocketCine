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
          label: 'Getting started', translations: { 'zh-TW': '開始' },
          items: [
            { label: 'Overview', translations: { 'zh-TW': '總覽' }, slug: '' },
            { label: 'Setup and build', translations: { 'zh-TW': '安裝與建置' }, slug: 'guides/setup' },
            { label: 'Troubleshooting', translations: { 'zh-TW': '疑難排解' }, slug: 'guides/troubleshooting' },
          ],
        },
        {
          label: 'Apps', translations: { 'zh-TW': '應用程式' },
          items: [
            { label: 'iOS', translations: { 'zh-TW': 'iOS 版' }, slug: 'apps/ios' },
            { label: 'Android', translations: { 'zh-TW': 'Android 版' }, slug: 'apps/android' },
            { label: 'Multiview prototype', translations: { 'zh-TW': '多機畫面原型' }, slug: 'guides/multiview-prototype' },
          ],
        },
        {
          label: 'Osmo Devices', translations: { 'zh-TW': 'Osmo 裝置' },
          items: [
            { label: 'Device references', slug: 'devices' },
            {
              label: 'Osmo Pocket 3', translations: { 'zh-TW': 'Osmo Pocket 3' }, collapsed: true,
              items: [
                { label: 'Overview and evidence', slug: 'devices/pocket-3' },
                { label: 'Command comparison', slug: 'devices/pocket-3/commands' },
                { label: 'Shooting modes and formats', slug: 'devices/pocket-3/modes' },
                { label: 'Exposure, focus and audio', slug: 'devices/pocket-3/settings' },
                { label: 'Zoom and gimbal controls', slug: 'devices/pocket-3/controls' },
                { label: 'Original media', slug: 'devices/pocket-3/media' },
                { label: 'Mimo album and exports', slug: 'devices/pocket-3/album' },
                { label: 'Livestream', slug: 'devices/pocket-3/livestream' },
                { label: 'USB webcam', slug: 'devices/pocket-3/webcam' },
                { label: 'Connection and reconnect', slug: 'devices/pocket-3/connection' },
                { label: 'Coverage and implementation', slug: 'devices/pocket-3/coverage' },
              ],
            },
            {
              label: 'Osmo Pocket 4 Pro', translations: { 'zh-TW': 'Osmo Pocket 4 Pro' }, collapsed: true,
              items: [
                { label: 'Overview and evidence', slug: 'devices/pocket-4-pro' },
                { label: 'Command comparison', slug: 'devices/pocket-4-pro/commands' },
                { label: 'Slow Motion', slug: 'devices/pocket-4-pro/slow-motion' },
                { label: 'Photo and Live Photo', slug: 'devices/pocket-4-pro/photo' },
                { label: 'Coverage and implementation', slug: 'devices/pocket-4-pro/coverage' },
              ],
            },
            {
              label: 'Osmo Action 6', collapsed: true,
              items: [
                { label: 'Overview and evidence', slug: 'devices/action-6' },
                { label: 'Command comparison', slug: 'devices/action-6/commands' },
                { label: 'Capture coverage and media commands', slug: 'devices/action-6/coverage' },
                { label: 'Bluetooth and pairing', slug: 'devices/action-6/bluetooth' },
                { label: 'Connection and live view', slug: 'devices/action-6/connection' },
                { label: 'Video, aperture and exposure', slug: 'devices/action-6/settings' },
                { label: 'Shooting modes', slug: 'devices/action-6/modes' },
                { label: 'Orientation and device settings', slug: 'devices/action-6/device-settings' },
                { label: 'Stabilization and advanced controls', slug: 'devices/action-6/controls' },
                { label: 'Original media', slug: 'devices/action-6/media' },
                { label: 'Firmware and published specifications', slug: 'devices/action-6/specifications' },
              ],
            },
          ],
        },
        {
          label: 'Shared protocol', translations: { 'zh-TW': '共用通訊協定' },
          items: [
            { label: 'Connection spine', translations: { 'zh-TW': '連線主流程' }, slug: 'protocol/connection' },
            { label: 'BLE pairing', translations: { 'zh-TW': '藍牙配對' }, slug: 'protocol/ble' },
            { label: 'Camera Wi-Fi', translations: { 'zh-TW': '相機 Wi-Fi' }, slug: 'protocol/wifi' },
            { label: 'DUML frame', translations: { 'zh-TW': 'DUML 封包格式' }, slug: 'protocol/duml-frame' },
            { label: 'DUML transport', translations: { 'zh-TW': 'DUML 傳輸層' }, slug: 'protocol/duml-transport' },
            { label: 'Command catalog', translations: { 'zh-TW': '指令清單' }, slug: 'protocol/commands' },
            { label: 'Live view', translations: { 'zh-TW': '即時畫面' }, slug: 'protocol/live-view' },
            { label: 'HTTP media', translations: { 'zh-TW': 'HTTP 媒體' }, slug: 'protocol/media' },
            { label: 'iOS notes', translations: { 'zh-TW': 'iOS 筆記' }, slug: 'protocol/ios' },
          ],
        },
        {
          label: 'Development', translations: { 'zh-TW': '開發' },
          items: [
            { label: 'Architecture', translations: { 'zh-TW': '架構' }, slug: 'apps/architecture' },
            { label: 'Keeping docs current', translations: { 'zh-TW': '文件維護' }, slug: 'contribute/documentation' },
          ],
        },
        {
          label: 'Release notes', translations: { 'zh-TW': '版本說明' },
          items: [
            { label: 'Open beta 102', translations: { 'zh-TW': '公開測試 102 版' }, slug: 'releases/beta-102' },
          ],
        },
      ],
    }),
  ],
});
