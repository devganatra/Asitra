export type AsitraAIContract = {
  version: number;
  profile: string;
  label: string;
  model: string;
  provider?: string;
};

export const ASITRA_AI_CONTRACT: AsitraAIContract = Object.freeze({
  version: 1,
  profile: "Everyday",
  label: "Terra",
  model: "gpt-5.6-terra",
});
