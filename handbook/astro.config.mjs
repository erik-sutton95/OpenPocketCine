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
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/erik-sutton95/OpenPocketCine',
        },
      ],
      sidebar: [
        {
          label: 'Start',
          items: [
            { label: 'Overview', slug: '' },
            { label: 'Setup and build', slug: 'guides/setup' },
            { label: 'Keeping docs current', slug: 'contribute/documentation' },
          ],
        },
        {
          label: 'Apps',
          items: [
            { label: 'Architecture', slug: 'apps/architecture' },
            { label: 'iOS', slug: 'apps/ios' },
            { label: 'Android', slug: 'apps/android' },
          ],
        },
        {
          label: 'Protocol',
          items: [
            { label: 'Connection spine', slug: 'protocol/connection' },
            { label: 'BLE pairing', slug: 'protocol/ble' },
            { label: 'Camera Wi-Fi', slug: 'protocol/wifi' },
            { label: 'DUML frame', slug: 'protocol/duml-frame' },
            { label: 'DUML transport', slug: 'protocol/duml-transport' },
            { label: 'Command catalog', slug: 'protocol/commands' },
            { label: 'Live view', slug: 'protocol/live-view' },
            { label: 'HTTP media', slug: 'protocol/media' },
            { label: 'iOS notes', slug: 'protocol/ios' },
          ],
        },
      ],
    }),
  ],
});
