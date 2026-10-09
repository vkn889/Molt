import { Composition } from "remotion";
import { MoltRelease, DURATION } from "./MoltRelease";

export const Root = () => (
  <Composition id="MoltRelease" component={MoltRelease} durationInFrames={DURATION} fps={30} width={1080} height={1920} />
);
