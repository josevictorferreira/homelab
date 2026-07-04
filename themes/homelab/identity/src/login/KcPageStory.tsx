import Template from "./Template";

const mockKcContext = {
  themeName: "homelab",
  themeType: "login",
  themeVersion: "0.1.0",
  keycloakifyVersion: "11.15.0",
  locale: {
    currentLanguageTag: "en",
    supported: [
      { url: "#en", label: "English", languageTag: "en" },
      { url: "#pt-BR", label: "Português (Brasil)", languageTag: "pt-BR" },
    ],
  },
  realm: {
    name: "homelab",
    displayName: "Homelab",
    displayNameHtml: "Homelab",
    internationalizationEnabled: true,
    registrationEmailAsUsername: false,
    loginWithEmailAllowed: true,
    resetPasswordAllowed: true,
    registrationAllowed: true,
    password: true,
    rememberMe: true,
  },
  url: {
    loginAction: "#",
    loginUrl: "#",
    loginRestartFlowUrl: "#",
    resourcesPath: "/resources",
    resourcesCommonPath: "/resources/common",
    ssoLoginInOtherTabsUrl: "",
    registrationUrl: "#",
    loginResetCredentialsUrl: "#",
  },
  auth: {},
  message: undefined,
  scripts: [],
  client: { clientId: "homelab-web" },
  messagesPerField: {
    existsError: () => false,
    get: (_field: string) => "",
    exists: (_field: string) => false,
    printIfExists: (_field: string, _text: string) => undefined,
  },
} as any;

export function LoginStory() {
  return (
    <Template kcContext={mockKcContext} i18n={{} as any} doUseDefaultCss={false} headerNode={<h1>Sign in to Homelab</h1>}>
      <p className="subtitle">Welcome back! Enter your credentials to continue.</p>
      <form>
        <div className="form-group">
          <label htmlFor="username">Username or Email</label>
          <input type="text" id="username" name="username" placeholder="Enter your username" autoFocus />
        </div>
        <div className="form-group">
          <label htmlFor="password">Password</label>
          <input type="password" id="password" name="password" placeholder="Enter your password" />
        </div>
        <div className="form-group" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <label className="checkbox-label">
            <input type="checkbox" name="rememberMe" /> Remember me
          </label>
          <a href="#">Forgot Password?</a>
        </div>
        <button type="submit" className="homelab-btn-primary">Log In</button>
      </form>
      <div style={{ textAlign: "center", marginTop: "24px" }}>
        <a href="#">Create an account</a>
      </div>
    </Template>
  );
}

export function RegisterStory() {
  return (
    <Template kcContext={{ ...mockKcContext, pageId: "register.ftl" }} i18n={{} as any} doUseDefaultCss={false} headerNode={<h1>Create your account</h1>}>
      <p className="subtitle">Access the homelab cluster services.</p>
      <form>
        <div className="form-group">
          <label htmlFor="firstName">First Name</label>
          <input type="text" id="firstName" name="firstName" placeholder="Enter your first name" />
        </div>
        <div className="form-group">
          <label htmlFor="lastName">Last Name</label>
          <input type="text" id="lastName" name="lastName" placeholder="Enter your last name" />
        </div>
        <div className="form-group">
          <label htmlFor="email">Email</label>
          <input type="email" id="email" name="email" placeholder="Enter your email" />
        </div>
        <div className="form-group">
          <label htmlFor="username">Username</label>
          <input type="text" id="username" name="username" placeholder="Choose a username" />
        </div>
        <div className="form-group">
          <label htmlFor="password">Password</label>
          <input type="password" id="password" name="password" placeholder="Create a password" />
        </div>
        <div className="form-group">
          <label htmlFor="password-confirm">Confirm Password</label>
          <input type="password" id="password-confirm" name="password-confirm" placeholder="Confirm your password" />
        </div>
        <button type="submit" className="homelab-btn-primary">Register</button>
      </form>
      <div style={{ textAlign: "center", marginTop: "24px" }}>
        <a href="#">Already have an account? Sign in</a>
      </div>
    </Template>
  );
}

export function ForgotPasswordStory() {
  return (
    <Template kcContext={{ ...mockKcContext, pageId: "login-reset-password.ftl" }} i18n={{} as any} doUseDefaultCss={false} headerNode={<h1>Forgot your password?</h1>}>
      <p className="subtitle">Enter your email and we'll send you a link to reset your password.</p>
      <form>
        <div className="form-group">
          <label htmlFor="email">Email</label>
          <input type="email" id="email" name="email" placeholder="Enter your email" autoFocus />
        </div>
        <button type="submit" className="homelab-btn-primary">Submit</button>
      </form>
      <div style={{ textAlign: "center", marginTop: "24px" }}>
        <a href="#">Back to login</a>
      </div>
    </Template>
  );
}

export function ErrorStory() {
  return (
    <Template kcContext={{ ...mockKcContext, pageId: "error.ftl", message: { type: "error", summary: "Something went wrong. Please try again." } }} i18n={{} as any} doUseDefaultCss={false} headerNode={<h1>Something went wrong</h1>}>
      <p className="subtitle">An unexpected error occurred. Please try again later.</p>
      <div style={{ textAlign: "center", marginTop: "24px" }}>
        <a href="#" className="homelab-btn-primary" style={{ display: "inline-flex", width: "auto" }}>
          Back to login
        </a>
      </div>
    </Template>
  );
}
