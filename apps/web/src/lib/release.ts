export const REPO = 'wuguishifu/macros';
export const REPO_URL = `https://github.com/${REPO}`;
export const RELEASES_URL = `${REPO_URL}/releases/latest`;

/** How long (seconds) a fetched release is reused before GitHub is asked again. */
export const RELEASE_REVALIDATE_SECONDS = 600;

export interface LatestRelease {
  version: string;
  dmgUrl: string;
  dmgSizeBytes: number;
  publishedAt: string;
  releaseUrl: string;
}

interface GitHubRelease {
  tag_name: string;
  html_url: string;
  published_at: string;
  assets: { name: string; size: number; browser_download_url: string }[];
}

/**
 * The latest published release and its DMG, or null if GitHub can't be reached or the release has no DMG.
 * Set GITHUB_TOKEN to lift the unauthenticated API rate limit.
 */
export async function getLatestRelease(): Promise<LatestRelease | null> {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  try {
    const res = await fetch(
      `https://api.github.com/repos/${REPO}/releases/latest`,
      {
        headers,
        next: { revalidate: RELEASE_REVALIDATE_SECONDS },
      },
    );
    if (!res.ok) return null;

    const release = (await res.json()) as GitHubRelease;
    const dmg = release.assets.find((asset) => asset.name.endsWith('.dmg'));
    if (!dmg) return null;

    return {
      version: release.tag_name.replace(/^v/, ''),
      dmgUrl: dmg.browser_download_url,
      dmgSizeBytes: dmg.size,
      publishedAt: release.published_at,
      releaseUrl: release.html_url,
    };
  } catch {
    return null;
  }
}

export function formatSize(bytes: number): string {
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}
