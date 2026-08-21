// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Local preview uses the site root (`just handbook` → http://localhost:4321/).
// A `/docs/` base path is only needed if this is later merged into GitHub Pages.
export default defineConfig({
  site: 'https://openpocketcine.app',
  integrations: [
    starlight({
      title: 'OpenPocketCine',
      description:
        'Protocol handbook: BLE pairing, camera Wi-Fi, and DUML as implemented in OpenPocketCine.',
      logo: {
        src: './src/assets/icon.png',
        alt: 'OpenPocketCine',
      },
      favicon: '/favicon.png',
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/erik-sutton95/OpenPocketCine',
        },
      ],
      sidebar: [
        {
          label: 'Protocol',
          items: [
            { label: 'Overview', slug: '' },
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
