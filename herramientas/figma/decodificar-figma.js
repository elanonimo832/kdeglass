#!/usr/bin/env node
/**
 * decodificar-figma.js — Pasa un kit de Figma (.fig) a JSON
 *
 * PARA QUE SIRVE
 * Un .fig no es un formato opaco: es un ZIP con un payload binario Kiwi, y ese
 * payload lleva DENTRO su propio esquema. Se lee el esquema, se compila y se usa
 * para decodificar el documento. De ahi salen los valores reales del kit
 * (radios, colores, alfas, tamanos de texto) como datos, no como impresiones.
 *
 * FORMATO DEL PAYLOAD (canvas.fig dentro del ZIP)
 *   [8]  "fig-kiwi"
 *   [4]  version (uint32 LE)
 *   [4]  longitud del chunk de esquema (uint32 LE)
 *   [N]  esquema   -> deflate CRUDO (sin cabecera)
 *   [4]  longitud del chunk de datos (uint32 LE)
 *   [M]  datos     -> zstd SIN cabecera de trama: [uint32 LE tamano crudo][bloques]
 *
 * EL DETALLE QUE ROMPE TODO: el chunk de datos no empieza por el numero magico
 * de zstd. Son bloques zstd en crudo precedidos por el tamano sin comprimir.
 * Para descomprimirlo hay que reinsertar la cabecera magica (28 B5 2F FD) delante.
 * Sin eso, zstd responde "unknown frame descriptor".
 *
 * USO
 *   node decodificar-figma.js kit.fig [salida.json]
 *
 * REQUIERE
 *   node >= 18, y las dependencias del package.json de esta carpeta.
 */

'use strict';

const fs = require('fs');
const zlib = require('zlib');
const { execFileSync } = require('child_process');
const pako = require('pako');
const kiwi = require('kiwi-schema');

const FIRMA_KIXI = Buffer.from('fig-kiwi');
const MAGIC_ZSTD = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);

/** Saca el payload Kiwi del ZIP. No hace falta dependencia de zip: se busca la firma. */
function extraerPayload(buf, verbose) {
  const i = buf.indexOf(FIRMA_KIXI);
  if (i < 0) {
    throw new Error(
      'no se encontro la firma "fig-kiwi" en el fichero.\n' +
      '  Causas tipicas: el fichero es un .json (Variables export), o el ZIP usa otra version.\n' +
      `  Primeros bytes: ${buf.slice(0, 16).toString('hex')}`
    );
  }
  if (verbose && i > 0) {
    console.log(`      (la firma estaba en el desplazamiento ${i}: cabecera ZIP de ${i} bytes)`);
  }
  return buf.slice(i);
}

/** Lee las longitudes declaradas y separa los dos chunks. */
function trocearPayload(p) {
  const version = p.readUInt32LE(8);
  const lenEsquema = p.readUInt32LE(12);
  const esquemaComprimido = p.slice(16, 16 + lenEsquema);
  const off = 16 + lenEsquema;
  const lenDatos = p.readUInt32LE(off);
  const datosComprimidos = p.slice(off + 4, off + 4 + lenDatos);
  return {
    version, esquemaComprimido, datosComprimidos,
    bytesSinUsar: p.length - (off + 4 + lenDatos),
  };
}

/**
 * El esquema va en deflate CRUDO (sin cabecera zlib) en los .fig reales.
 *
 * Trampa importante: `pako.inflate()` (esperando zlib envuelto) NO lanza excepcion
 * si le pasas deflate crudo con esta forma; devuelve el buffer de entrada tal cual.
 * Por eso hay que probar `inflateRaw` PRIMERO y, ademas, comprobar que el resultado
 * tiene pinta de esquema Kiwi (texto), en lugar de fiarse de que no haya excepcion.
 */
function descomprimirEsquema(chunk) {
  const intentos = [
    { nombre: 'deflate crudo', fn: () => pako.inflateRaw(chunk) },
    { nombre: 'zlib envuelto', fn: () => pako.inflate(chunk) },
  ];
  const fallos = [];
  for (const it of intentos) {
    try {
      const out = it.fn();
      // Comprobacion de cordura: un esquema Kiwi es texto con definiciones.
      if (out && out.length > 16 && out.length !== chunk.length) {
        return { datos: out, via: it.nombre };
      }
      fallos.push(`${it.nombre}: resultado sospechoso (${out ? out.length : 0} bytes)`);
    } catch (e) {
      fallos.push(`${it.nombre}: ${e.message}`);
    }
  }
  throw new Error('no se pudo descomprimir el esquema.\n  ' + fallos.join('\n  '));
}

/**
 * Descomprime el chunk de datos.
 *
 * CORRECCION IMPORTANTE sobre versiones anteriores de esta herramienta: en un .fig
 * REAL el chunk ya es un FRAME ZSTD COMPLETO, empezando por el numero magico
 * (28 B5 2F FD) y con su propia cabecera de trama. NO hay que reinsertar nada.
 * Los 4 primeros bytes son la cabecera de trama, no un tamano.
 *
 * Se conserva el camino alternativo ([uint32 tamano crudo][bloques]) porque algunas
 * herramientas de terceros montan asi el chunk. La eleccion se hace mirando el
 * numero magico, no por suposicion.
 */
function descomprimirDatos(chunk) {
  const esFrameCompleto =
    chunk.length > 4 &&
    chunk[0] === 0x28 && chunk[1] === 0xb5 && chunk[2] === 0x2f && chunk[3] === 0xfd;

  // El CLI de zstd va PRIMERO, y no es un detalle menor: `fzstd` falla en silencio
  // con tramas que usan ventana grande + tamano de contenido declarado (descriptor
  // 0x80). Devuelve bytes sin error y el fallo aparece despues, como "Invalid type"
  // del decodificador Kiwi, que despista por completo. Verificado con el kit real.
  const intentos = [];
  if (esFrameCompleto) {
    intentos.push({ nombre: 'frame zstd completo', datos: chunk, tamanoCrudo: 0 });
  } else {
    intentos.push({
      nombre: 'magic reinsertado [uint32][bloques]',
      datos: Buffer.concat([MAGIC_ZSTD, chunk.slice(4)]),
      tamanoCrudo: chunk.readUInt32LE(0),
    });
    intentos.push({ nombre: 'tal cual', datos: chunk, tamanoCrudo: 0 });
  }

  const errores = [];
  for (const intento of intentos) {
    const tmp = `/tmp/_fig_${process.pid}_${Date.now()}.zst`;
    try {
      fs.writeFileSync(tmp, intento.datos);
      const out = execFileSync('zstd', ['-d', '-q', '-c', tmp], { maxBuffer: 1 << 31 });
      return { datos: out, via: `zstd CLI (${intento.nombre})`, tamanoCrudo: intento.tamanoCrudo };
    } catch (e) {
      errores.push(`${intento.nombre}: ${(e.stderr || e.message).toString().slice(0, 80)}`);
    } finally {
      try { fs.unlinkSync(tmp); } catch (_) {}
    }
  }

  // Ultimo recurso: fzstd, avisando de que su salida hay que verificarla.
  try {
    const fzstd = require('fzstd');
    const out = Buffer.from(fzstd.decompress(chunk));
    console.log('      AVISO: descomprimido con fzstd (sin verificar). Si falla la decodificacion,');
    console.log('             es probable que fzstd no soporte esta trama: hace falta el CLI de zstd.');
    return { datos: out, via: 'fzstd (sin verificar)', tamanoCrudo: 0 };
  } catch (_) { /* nada mas que probar */ }

  throw new Error(
    'no se pudieron descomprimir los datos zstd.\n  ' + errores.join('\n  ') +
    '\n  Comprueba que el comando `zstd` esta instalado.'
  );
}

function main() {
  const ruta = process.argv[2];
  const salida = process.argv[3] || 'kit.json';
  if (!ruta) {
    console.error('uso: node decodificar-figma.js <fichero.fig> [salida.json]');
    process.exit(2);
  }
  if (!fs.existsSync(ruta)) {
    console.error(`ERROR: no existe ${ruta}`);
    process.exit(1);
  }

  const buf = fs.readFileSync(ruta);
  console.log(`[1/5] Leido ${ruta}: ${(buf.length / 1e6).toFixed(2)} MB`);

  const payload = extraerPayload(buf, true);
  console.log(`[2/5] Payload Kiwi: ${(payload.length / 1e6).toFixed(2)} MB`);

  const { version, esquemaComprimido, datosComprimidos, bytesSinUsar } = trocearPayload(payload);
  console.log(`[3/5] version=${version} | esquema=${esquemaComprimido.length} B | datos=${datosComprimidos.length} B | resto=${bytesSinUsar} B`);

  const { datos: esquemaBin, via: viaEsquema } = descomprimirEsquema(esquemaComprimido);
  const schema = kiwi.decodeBinarySchema(esquemaBin);
  const nTipos = (schema.definitions || []).length;
  console.log(`[4/5] Esquema: ${nTipos} tipos (descomprimido por ${viaEsquema})`);
  if (nTipos < 50) {
    console.log(`      AVISO: un kit real define cientos de tipos. Con ${nTipos} algo no cuadra.`);
  }

  const { datos: datosBin, via: viaDatos, tamanoCrudo } = descomprimirDatos(datosComprimidos);
  console.log(`[5/5] Datos: ${(datosBin.length / 1e6).toFixed(2)} MB (declarado ${(tamanoCrudo / 1e6).toFixed(2)} MB, via ${viaDatos})`);
  if (tamanoCrudo && datosBin.length !== tamanoCrudo) {
    console.log(`      AVISO: el tamano no coincide con el declarado. Revisar antes de fiarse.`);
  }

  // El nombre del decodificador depende del tipo raiz del esquema: no siempre se
  // llama `decodeMessage`. Se busca cual expone el modulo compilado.
  const compiled = kiwi.compileSchema(schema);
  const decodificadores = Object.keys(compiled).filter((k) => k.startsWith('decode'));
  if (decodificadores.length === 0) {
    throw new Error('el esquema compilado no expone ningun decodificador. Tipos: ' + Object.keys(compiled).join(', '));
  }
  // Preferimos los nombres habituales en kits de Figma; si no, el primero disponible.
  const preferidos = ['decodeMessage', 'decodeMensaje', 'decodeNodeChanges', 'decodeDocument'];
  const nombre = preferidos.find((n) => decodificadores.includes(n)) || decodificadores[0];
  console.log(`      decodificador usado: ${nombre} (disponibles: ${decodificadores.join(', ')})`);

  const message = compiled[nombre].call(compiled, datosBin);
  console.log(`      Documento decodificado. Claves raiz: ${Object.keys(message).join(', ')}`);

  fs.writeFileSync(
    salida,
    JSON.stringify(message, (_k, v) => (typeof v === 'bigint' ? Number(v) : v), 1)
  );
  console.log(`\nEscrito ${salida} (${(fs.statSync(salida).size / 1e6).toFixed(1)} MB)`);

  const nc = message.nodeChanges || [];
  console.log(`nodeChanges: ${nc.length} nodos`);
  console.log('\nSiguiente paso: node extraer-tokens.js ' + salida);
}

if (require.main === module) {
  try {
    main();
  } catch (e) {
    console.error(`\nERROR: ${e.message}`);
    process.exit(1);
  }
}

module.exports = { extraerPayload, trocearPayload, descomprimirEsquema, descomprimirDatos };
