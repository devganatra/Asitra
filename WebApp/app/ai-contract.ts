export type SakhyaAIContract = {
  version: number;
  profile: string;
  label: string;
  model: string;
  provider?: string;
};

export const SAKHYA_AI_CONTRACT: SakhyaAIContract = Object.freeze({
  version: 1,
  profile: "Everyday",
  label: "Terra",
  model: "gpt-5.6-terra",
});
