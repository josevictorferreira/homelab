import { lazy, Suspense } from "react";
import type { KcContext } from "./KcContext";
import Template from "./Template";
import { useI18n } from "./i18n";

const DefaultPage = lazy(() => import("keycloakify/login/DefaultPage"));
const UserProfileFormFields = lazy(() => import("keycloakify/login/UserProfileFormFields"));

export default function KcPage(props: { kcContext: KcContext }) {
  const { kcContext } = props;
  const { i18n } = useI18n({ kcContext });

  return (
    <Suspense>
      <DefaultPage
        kcContext={kcContext}
        Template={Template}
        doUseDefaultCss={true}
        i18n={i18n}
        UserProfileFormFields={UserProfileFormFields}
        doMakeUserConfirmPassword={false}
      />
    </Suspense>
  );
}
