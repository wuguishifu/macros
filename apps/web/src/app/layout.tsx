import type { Metadata } from 'next';
import './global.css';

export const metadata: Metadata = {
  title: 'Macros: vim-style macros for macOS',
  description:
    'Record keyboard and mouse input into a register, then replay it as many times as you need. A free, open-source menu bar app for macOS.',
  openGraph: {
    title: 'Macros',
    description: 'Vim-style keyboard and mouse macros for macOS.',
    type: 'website',
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
