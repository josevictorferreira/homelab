{ kubenix, homelab, ... }:

let
  app = "oratoria";
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes.resources.secrets."${app}-config" = {
    metadata = {
      name = "${app}-config";
      inherit namespace;
    };
    stringData = {
      OMNIROUTE_API_KEY = kubenix.lib.secretsFor "omniroute_api_key";
      OMNIROUTE_BASE_URL = "https://omniroute.josevictor.me";
      ELEVENLABS_API_KEY = kubenix.lib.secretsFor "elevenlabs_api_key";
      ELEVENLABS_MODEL = "eleven_v3";
      SUPERTONIC_BASE_URL = "http://10.10.10.10:7788";
      GEPARD_BASE_URL = "http://10.10.10.10:8000";
      QWEN3_TTS_BASE_URL = "http://10.10.10.10:8000";
      HIGGS_BASE_URL = "http://10.10.10.10:8095";
      OMNIVOICE_BASE_URL = "http://10.10.10.10:8001";
      FISH_SPEECH_BASE_URL = "http://10.10.10.10:8080";
    };
  };
}
