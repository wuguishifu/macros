import { NextResponse } from 'next/server';
import { getLatestRelease, RELEASES_URL } from '../../lib/release';

/** Stable link to the newest DMG: /download redirects to the latest release asset. */
export async function GET() {
  const release = await getLatestRelease();
  return NextResponse.redirect(release?.dmgUrl ?? RELEASES_URL, 302);
}
