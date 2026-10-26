// Native runtime independently checks this same exact version/build/UUID matrix.
export const inspectedHosts = Object.freeze([
  Object.freeze({version:'1.0.6',build:'218',uuid:'98a03b57e8163ba19778e55fabe8d762'}),
  Object.freeze({version:'1.0.2',build:'67',uuid:'eeea85e54114313cb65173c90a6b5d3c'}),
  Object.freeze({version:'1.0.4',build:'195',uuid:'261c8e78f9553d7d85f713b9082972cf'}),
  Object.freeze({version:'1.0.5',build:'201',uuid:'748fd301da603095a2449bd0558faca5'}),
]);
export function inspectedHost(info, uuid) {
  if(info.CFBundleIdentifier!=='com.rayneo.venus.pub'||info.CFBundleExecutable!=='Runner')return null;
  return inspectedHosts.find(h=>h.version===info.CFBundleShortVersionString&&h.build===String(info.CFBundleVersion)&&h.uuid===uuid)??null;
}
