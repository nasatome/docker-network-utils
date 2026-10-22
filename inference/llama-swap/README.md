# llama-swap — Servicio global de inferencia LLM/VLM

Proxy con hot-swap de modelos basado en
[mostlygeek/llama-swap](https://github.com/mostlygeek/llama-swap). Un único
endpoint compatible con la API de OpenAI para todos los proyectos del host:
carga el modelo que pide cada request, y lo descarga tras un periodo de
inactividad para liberar la VRAM.

## La infraestructura vive aquí, tu catálogo vive fuera

Este repositorio es público y genérico. Publica **cómo se despliega el
servicio**, no qué modelos tiene nadie en su disco.

```
inference/llama-swap/
├── docker-compose.yml                  el servicio
├── .env.example                        plantilla de configuración
├── config/llama-swap.yaml.example      plantilla de catálogo, 2 modelos + 1 patrón
└── scripts/                            red + healthcheck

~/.config/llama-swap/catalog.yaml       TU catálogo real (fuera del repo)
```

El puente entre ambos es una variable:

```bash
# .env
LLAMA_SWAP_CONFIG=/home/tu-usuario/.config/llama-swap/catalog.yaml
```

Si no la defines, el compose monta `config/llama-swap.yaml.example` y el
servicio arranca igual, con los modelos de ejemplo. Eso hace que un clon limpio
funcione sin configurar nada, y que tu catálogo real nunca pueda entrar a un
commit por accidente: `.gitignore` bloquea `config/llama-swap.yaml` por nombre.

Para empezar tu catálogo, copia la plantilla fuera del repo y edítala ahí:

```bash
mkdir -p ~/.config/llama-swap && cp config/llama-swap.yaml.example ~/.config/llama-swap/catalog.yaml
```

## Setup inicial

```bash
cp .env.example .env             # edita MODELS_ROOT como mínimo
./scripts/init-network.sh        # crea la red ai_inference (idempotente)
docker compose up -d
./scripts/doctor.sh              # health + lista de modelos + estado de GPU
```

`MODELS_ROOT` es obligatoria y apunta al directorio del host con tus GGUF. Se
monta read-only en `/models`, y las rutas de tu catálogo se escriben relativas a
ese punto. Hay dos montajes opcionales más (`MODELS_ROOT_FAST` en
`/models-fast`, `EXTRA_MODELS_ROOT` en `/extra-models`) para repartir modelos
entre discos; ambos caen a un placeholder inocuo si no los defines.

## Añadir un modelo

1. Descarga el GGUF bajo `MODELS_ROOT` (y su `mmproj` si es multimodal).
2. Añade la entrada a tu catálogo, con la ruta relativa a `/models`.
3. `docker compose restart`.

`config/llama-swap.yaml.example` documenta los patrones disponibles: modelo de
texto, modelo multimodal con `--mmproj`, y descarga de expertos a CPU para MoE
que no caben en la GPU. Cada flag lleva explicado qué hace y cómo calibrarlo.

## Puertos

- **Container interno**: `8080`, donde escucha el daemon (fijo en la imagen).
- **Host**: `127.0.0.1:${HOST_PORT}` (por defecto `8222`), para clientes no
  dockerizados.
- **Red docker `ai_inference`**: los containers consumidores usan
  `http://llama-swap:8080`.

## Cómo consumir desde otros proyectos (opt-in)

Añade a tu `docker-compose.yml`:

```yaml
networks:
  ai_inference:
    external: true

services:
  app:
    networks:
      - default                  # red propia del proyecto, no cambia
      - ai_inference             # acceso a llama-swap
    environment:
      LLAMA_SERVER_URL: http://llama-swap:8080
      LLAMA_MODEL_NAME: qwen3.5-4b
```

Request compatible con OpenAI. El campo `model` es obligatorio y es lo que
decide qué modelo se carga:

```bash
curl http://llama-swap:8080/v1/chat/completions -H "Content-Type: application/json" -d '{"model": "qwen3.5-4b", "messages": [{"role": "user", "content": "ping"}], "max_tokens": 16}'
```

Desde un proyecto no dockerizado, lo mismo contra `http://127.0.0.1:8222`.

## Modelos de razonamiento: apagar el pensamiento para tareas mecánicas

Vale para cualquier catálogo, y es contraintuitivo lo suficiente como para
documentarlo.

Muchos modelos recientes razonan por defecto: emiten una cadena de pensamiento
antes de responder. Esos tokens **se pagan** aunque el cliente sólo lea el
`content`. La mayoría permite apagarlo por petición:

```jsonc
{"model": "...", "messages": [...],
 "chat_template_kwargs": {"enable_thinking": false}}
```

**Para clasificar, extraer o reformatear, apagarlo suele MEJORAR el resultado, no
sólo abaratarlo.** Medido sobre una tarea de clasificación con seis modelos:

- Con un prompt que sólo listaba las categorías, apagar el razonamiento costaba
  aciertos. **Con un prompt que define qué significa cada categoría, apagarlo los
  sube** — y cuesta ~6× menos tokens y ~5× menos tiempo. El razonamiento estaba
  compensando un prompt pobre. **Invertir en las definiciones rinde más que
  encender el pensamiento.**
- **La varianza entre corridas es del razonamiento, no del modelo.** Con
  pensamiento, el mismo modelo variaba ±49% en tokens entre dos corridas — el
  modelo decide cuánto pensar cada vez. Apagado, cuatro corridas dieron el mismo
  resultado con ±6% de tokens. Si un ranking necesita promediar cinco corridas,
  vale la pena preguntarse si conviene quitar la fuente de varianza en vez de
  medirla.
- **«Razonar poco» puede ser peor que no razonar.** Un modelo con esfuerzo bajo
  acertó *menos* que el mismo modelo apagado, gastando 5× más tokens.

### Tres avisos prácticos

**No todos obedecen.** Hay plantillas de chat que inyectan el bloque de
pensamiento sin interruptor: mandar `enable_thinking: false` no hace nada y no
avisa. Compruébalo mirando `completion_tokens`, no la documentación.

**`finish_reason: length` no es una respuesta.** Un modelo de razonamiento que se
queda sin presupuesto devuelve `content` **vacío y sin error**: gastó todo el
cupo pensando. Desde fuera es indistinguible de una respuesta legítimamente
vacía. Trátalo siempre como fallo ruidoso.

**Un benchmark de código no predice el resto.** Cinco modelos que resolvían igual
de bien un ejercicio de programación se separaron mucho en una tarea de
clasificación — y el que había quedado descartado *por lento* resultó el mejor y
el más rápido en cuanto se le apagó el pensamiento. Mide la tarea que vas a
correr.

## Modelo de confianza

**llama-swap no tiene autenticación.** Cualquier container conectado a la red
`ai_inference` puede invocar `/v1/chat/completions`, `/v1/models` y los
endpoints de administración (logs, unload).

Es aceptable en el setup por defecto porque:

- El puerto del host está atado a `127.0.0.1`, no expuesto a la LAN.
- La red `ai_inference` es opt-in: solo la ven los proyectos a los que les
  añades `networks: [ai_inference]`.
- Asume un host de un solo usuario o de un equipo que ya confía entre sí.

**Si eso no describe tu caso** —un proyecto de un tercero, o un container desde
una red no confiable— añade `apiKeys` al catálogo y un middleware Bearer en los
consumidores antes de exponerlo.

## Troubleshooting

- `./scripts/doctor.sh` — health, modelos cargados y estado de la GPU.
- `docker logs llama-swap -f` — logs en tiempo real.
- `nvidia-smi` — VRAM ocupada.
- Un modelo nuevo no aparece: comprueba que editaste el archivo al que apunta
  `LLAMA_SWAP_CONFIG` y no una copia dentro del repo, y reinicia.
- Timeout en el primer request a un modelo: sube `healthCheckTimeout`. El cold
  start lee el GGUF entero desde disco.
