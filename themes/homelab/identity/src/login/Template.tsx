import type { TemplateProps } from "keycloakify/login/TemplateProps";
import "./main.css";

export default function Template(props: TemplateProps<any, any>) {
  const { kcContext, children, headerNode, infoNode, socialProvidersNode, displayMessage } = props;
  const { realm, url, message } = kcContext;

  return (
    <div className="homelab-shell">
      <div className="homelab-grid-bg" aria-hidden="true" />
      <div className="homelab-scanlines" aria-hidden="true" />

      <header className="homelab-header">
        <div className="homelab-header-inner">
          <a href={url.loginUrl} className="homelab-logo">
            <span className="homelab-logo-icon" aria-hidden="true">
              <svg viewBox="0 0 32 32" width="32" height="32" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="M4 28 L4 4 L12 4 L20 16 L12 28 Z" />
                <path d="M18 28 L22 20 L26 28" />
                <circle cx="22" cy="12" r="2" fill="currentColor" stroke="none" />
              </svg>
            </span>
            <span className="homelab-logo-text">HOMELAB</span>
          </a>
          {realm.internationalizationEnabled && kcContext.locale && (
            <div className="homelab-locale">
              <select
                id="locale-select"
                aria-label="Language"
                defaultValue={kcContext.locale.currentLanguageTag}
                onChange={(e) => {
                  window.location.href = e.target.value;
                }}
              >
                {kcContext.locale.supported.map((l: { url: string; label: string }) => (
                  <option key={l.url} value={l.url}>
                    {l.label}
                  </option>
                ))}
              </select>
            </div>
          )}
        </div>
      </header>

      <main className="homelab-main">
        <div className="homelab-card">
          {headerNode}
          {displayMessage && message !== undefined && (
            <div
              className={`homelab-alert homelab-alert--${message.type}`}
              role="alert"
            >
              <span className="homelab-alert-icon" aria-hidden="true" />
              <span>{message.summary}</span>
            </div>
          )}
          {children}
          {socialProvidersNode}
          {infoNode && <div className="homelab-registration">{infoNode}</div>}
        </div>
      </main>

      <footer className="homelab-footer">
        <p>&copy; {new Date().getFullYear()} HOMELAB // ACCESS TERMINAL</p>
      </footer>
    </div>
  );
}
