<template>
  <div ref="containerRef" class="ueditor-field" :data-editor-id="editorId" :data-ueditor-ready="ready ? 'true' : 'false'"></div>
</template>

<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'

const props = defineProps<{
  modelValue: string
}>()
const emit = defineEmits<{
  'update:modelValue': [value: string]
  ready: []
}>()

const editorId = `editor_${Math.random().toString(36).slice(2)}`
const containerRef = ref<HTMLElement>()
const ready = ref(false)
let editor: UEditorInstance | null = null
let editorNode: HTMLScriptElement | null = null

onMounted(async () => {
  editorNode = document.createElement('script')
  editorNode.id = editorId
  editorNode.type = 'text/plain'
  containerRef.value?.appendChild(editorNode)

  const ue = await loadUeditorScripts()
  disableUnstableUeditorPlugins(ue)
  await nextTick()
  editor = ue.getEditor(editorId, {
    elementPathEnabled: false,
    wordCount: false,
    scaleEnabled: false
  })
  editor.addListener('ready', () => {
    ready.value = true
    editor?.setContent(props.modelValue || '')
    editor?.addListener('contentchange', syncContent)
    emit('ready')
  })
})

onBeforeUnmount(() => {
  if (editor) {
    try {
      editor.removeListener?.('contentchange', syncContent)
      window.UE?.delEditor?.(editorId)
    } catch {
      // UEditor may throw when its iframe has already been removed during route changes.
    }
    editor = null
  }
  editorNode = null
})

watch(
  () => props.modelValue,
  (value) => {
    if (!ready.value || !editor) {
      return
    }

    if (editor.getContent() !== value) {
      editor.setContent(value || '')
    }
  }
)

function syncContent() {
  if (editor) {
    emit('update:modelValue', editor.getContent())
  }
}

const ueditorScripts = [
  'ueditor.config.js?v=3',
  'ueditor.all.js?v=3',
  'lang/zh-cn/zh-cn.js',
  'kityformula-plugin/addKityFormulaDialog.js',
  'kityformula-plugin/getKfContent.js',
  'kityformula-plugin/defaultFilterFix.js'
]
let ueditorLoadPromise: Promise<UEditorGlobal> | null = null

function getUeditorBaseUrl() {
  const base = import.meta.env.BASE_URL || './'
  return `${base.replace(/\/?$/, '/')}admin/components/ueditor/`
}

function loadScript(src: string) {
  return new Promise<void>((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(`script[src="${src}"]`)
    if (existing) {
      resolve()
      return
    }

    const script = document.createElement('script')
    script.src = src
    script.onload = () => resolve()
    script.onerror = () => reject(new Error(`UEditor script load failed: ${src}`))
    document.head.appendChild(script)
  })
}

function loadUeditorScripts() {
  if (!ueditorLoadPromise) {
    const baseUrl = getUeditorBaseUrl()
    window.UEDITOR_HOME_URL = baseUrl
    ueditorLoadPromise = loadScript(baseUrl + ueditorScripts[0])
      .then(() => {
        window.UEDITOR_HOME_URL = baseUrl
        if (window.UEDITOR_CONFIG) {
          window.UEDITOR_CONFIG.UEDITOR_HOME_URL = baseUrl
        }
        return ueditorScripts.slice(1).reduce((promise, script) => promise.then(() => loadScript(baseUrl + script)), Promise.resolve())
      })
      .then(() => {
        if (window.UEDITOR_CONFIG) {
          window.UEDITOR_CONFIG.UEDITOR_HOME_URL = baseUrl
        }
        if (!window.UE) {
          throw new Error('UEditor loaded but window.UE is unavailable')
        }
        return window.UE
      })
      .catch((error) => {
        ueditorLoadPromise = null
        throw error
      })
  }
  return ueditorLoadPromise
}

function disableUnstableUeditorPlugins(ue: UEditorGlobal) {
  // The bundled message UI plugin assumes editor.ui exists inside async ready
  // callbacks. In Vue route mounts that can race and throw, while the plugin is
  // not used by the question editor toolbar.
  delete ue._customizeUI?.message
}

interface UEditorInstance {
  addListener: (eventName: string, callback: () => void) => void
  removeListener?: (eventName: string, callback: () => void) => void
  destroy?: () => void
  getContent: () => string
  setContent: (content: string) => void
}

interface UEditorGlobal {
  getEditor: (id: string, options?: Record<string, unknown>) => UEditorInstance
  delEditor?: (id: string) => void
  _customizeUI?: Record<string, unknown>
}

declare global {
  interface Window {
    UE?: UEditorGlobal
    UEDITOR_HOME_URL?: string
    UEDITOR_CONFIG?: {
      UEDITOR_HOME_URL?: string
    }
  }
}
</script>
