import Image from 'next/image';
import type { ReactNode } from 'react';
import {
  formatSize,
  getLatestRelease,
  RELEASES_URL,
  REPO_URL,
} from '../lib/release';
import styles from './page.module.css';

// Re-render at most every 10 minutes so the download button follows new releases.
// Must be a literal for Next to read it; keep in sync with RELEASE_REVALIDATE_SECONDS.
export const revalidate = 600;

function Keys({ children }: { children: string }) {
  return <kbd className={styles.key}>{children}</kbd>;
}

function Chord({ keys }: { keys: string[] }) {
  return (
    <span className={styles.chord}>
      {keys.map((key, i) => (
        <Keys key={i}>{key}</Keys>
      ))}
    </span>
  );
}

async function DownloadButton() {
  const release = await getLatestRelease();

  if (!release) {
    return (
      <div className={styles.download}>
        <a className={styles.downloadButton} href={RELEASES_URL}>
          Download from GitHub
        </a>
        <p className={styles.downloadMeta}>macOS 14 Sonoma or later</p>
      </div>
    );
  }

  return (
    <div className={styles.download}>
      <a className={styles.downloadButton} href={release.dmgUrl}>
        Download for macOS
      </a>
      <p className={styles.downloadMeta}>
        <a href={release.releaseUrl}>v{release.version}</a> ·{' '}
        {formatSize(release.dmgSizeBytes)} · macOS 14 Sonoma or later
      </p>
    </div>
  );
}

const steps: {
  title: string;
  chord: string[];
  hud: string;
  body: ReactNode;
}[] = [
  {
    title: 'Record',
    chord: ['⌃⌘M', 'a'],
    hud: '● REC @a',
    body: (
      <>
        Press the record shortcut, then a letter. That letter is the register
        your macro goes into. Hold <Keys>⇧</Keys> on the letter to append
        instead of overwrite.
      </>
    ),
  },
  {
    title: 'Do the thing once',
    chord: [],
    hud: '● REC @a',
    body: 'Type, click, drag and scroll as usual. Macros captures keys, mouse movement, clicks and scrolling, with the timing between them.',
  },
  {
    title: 'Stop',
    chord: ['⌃⌘M'],
    hud: 'Recorded @a',
    body: 'Press the record shortcut again. The macro is saved to disk and survives restarts.',
  },
  {
    title: 'Replay',
    chord: ['⌃⌘N', '12', 'a'],
    hud: '▶ @a  3/12',
    body: (
      <>
        Press the play shortcut, an optional count and the register.{' '}
        <Keys>Esc</Keys> stops playback at any time.
      </>
    ),
  },
];

const shortcuts: { keys: string[]; does: string }[] = [
  { keys: ['⌃⌘M', 'a'], does: 'Record into register a' },
  { keys: ['⌃⌘M', '⇧A'], does: 'Record, appending to register a' },
  { keys: ['⌃⌘M'], does: 'Stop recording' },
  { keys: ['⌃⌘N', 'a'], does: 'Play register a' },
  { keys: ['⌃⌘N', '12', 'a'], does: 'Play register a 12 times' },
  { keys: ['⌃⌘N', '⌃⌘N'], does: 'Replay the last register' },
  { keys: ['Esc'], does: 'Cancel a chord, or stop playback' },
];

const tips: { title: string; body: string }[] = [
  {
    title: 'End where the next run starts',
    body: 'Finish each recording by moving to the next item: the next tab, row or file. Then repeats chain together.',
  },
  {
    title: 'Prefer the keyboard',
    body: 'Clicks replay at the same screen coordinates they were recorded at. Keyboard navigation keeps working if a window moves or a page loads a little differently.',
  },
  {
    title: 'Speed it up',
    body: 'Settings has playback speed (1×, 2×, 4×), a cap for long pauses, and an extra gap between repeats for slow pages.',
  },
  {
    title: 'Hands off while it runs',
    body: 'Your own keyboard and mouse are blocked during playback so they can’t interfere. Esc or the play shortcut always stops it.',
  },
];

const faqs: { q: string; a: ReactNode }[] = [
  {
    q: 'Why does it need Accessibility access?',
    a: 'macOS requires it for any app that watches for global shortcuts or sends keyboard and mouse input to other apps. Macros asks on first launch and walks you to the right System Settings pane.',
  },
  {
    q: 'Why isn’t it on the Mac App Store?',
    a: 'The App Store sandbox doesn’t allow apps to send input to other apps, which is the whole point. Releases are signed with a Developer ID and notarized by Apple instead.',
  },
  {
    q: 'Can I change the shortcuts?',
    a: (
      <>
        Yes. Both leaders are configurable in Settings. They need at least one
        of <Keys>⌘</Keys>
        <Keys>⌃</Keys>
        <Keys>⌥</Keys>.
      </>
    ),
  },
  {
    q: 'Does it record passwords?',
    a: 'No. Password fields turn on macOS Secure Input, which hides keystrokes from every app. The recording HUD warns you when that happens.',
  },
  {
    q: 'Where are macros stored?',
    a: (
      <>
        One JSON file per register in{' '}
        <code>~/Library/Application Support/Macros/registers</code>. Nothing
        leaves your Mac.
      </>
    ),
  },
];

export default function Index() {
  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <a className={styles.brand} href="#top">
          <Image src="/app-icon.svg" alt="" width={28} height={28} />
          Macros
        </a>
        <nav className={styles.nav}>
          <a href="#how">How it works</a>
          <a href="#uses">Use cases</a>
          <a href="#shortcuts">Shortcuts</a>
          <a href={REPO_URL}>GitHub</a>
        </nav>
      </header>

      <main id="top">
        <section className={styles.hero}>
          <Image
            className={styles.heroIcon}
            src="/app-icon.svg"
            alt="Macros app icon"
            width={128}
            height={128}
          />
          <h1>Vim-style macros for your whole Mac.</h1>
          <p className={styles.lede}>
            Record your keyboard and mouse into a register, then replay it as
            many times as you need. Macros lives in the menu bar and stays out
            of the way until you press a shortcut.
          </p>
          <DownloadButton />
          <div className={styles.heroDemo} aria-hidden="true">
            <Chord keys={['⌃⌘N', '20', 'a']} />
            <span className={styles.arrow}>→</span>
            <span className={styles.hud}>▶ @a 3/20</span>
          </div>
        </section>

        <section id="how" className={styles.section}>
          <h2>How it works</h2>
          <ol className={styles.steps}>
            {steps.map((step, i) => (
              <li key={step.title} className={styles.card}>
                <span className={styles.stepNumber}>{i + 1}</span>
                <h3>{step.title}</h3>
                <p>{step.body}</p>
                <div className={styles.stepFooter}>
                  {step.chord.length > 0 && <Chord keys={step.chord} />}
                  <span className={styles.hud}>{step.hud}</span>
                </div>
              </li>
            ))}
          </ol>
        </section>

        <section id="shortcuts" className={styles.section}>
          <h2>Shortcuts</h2>
          <p className={styles.sectionLede}>
            Registers are <Keys>a</Keys> to <Keys>z</Keys>. Counts go up to 999.
          </p>
          <table className={styles.table}>
            <tbody>
              {shortcuts.map((shortcut) => (
                <tr key={shortcut.does}>
                  <td>
                    <Chord keys={shortcut.keys} />
                  </td>
                  <td>{shortcut.does}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>

        <section className={styles.section}>
          <h2>Tips</h2>
          <div className={styles.grid}>
            {tips.map((tip) => (
              <article key={tip.title} className={styles.card}>
                <h3>{tip.title}</h3>
                <p>{tip.body}</p>
              </article>
            ))}
          </div>
        </section>

        <section className={styles.section}>
          <h2>Install</h2>
          <ol className={styles.install}>
            <li>Download the DMG and drag Macros into Applications.</li>
            <li>Open it. It shows up in the menu bar, not the Dock.</li>
            <li>
              Grant Accessibility access when asked. The permission window
              closes itself once you have.
            </li>
          </ol>
        </section>

        <section className={styles.section}>
          <h2>Questions</h2>
          <dl className={styles.faq}>
            {faqs.map((faq) => (
              <div key={faq.q}>
                <dt>{faq.q}</dt>
                <dd>{faq.a}</dd>
              </div>
            ))}
          </dl>
        </section>

        <section className={`${styles.section} ${styles.closing}`}>
          <h2>Stop doing it by hand.</h2>
          <DownloadButton />
        </section>
      </main>

      <footer className={styles.footer}>
        <span>Macros is free and open source under the MIT license.</span>
        <span className={styles.footerLinks}>
          <a href={REPO_URL}>Source</a>
          <a href={`${REPO_URL}/releases`}>Releases</a>
          <a href={`${REPO_URL}/issues`}>Report an issue</a>
        </span>
      </footer>
    </div>
  );
}
