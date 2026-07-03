<template>
  <div>
    <script :id="randomId" type="text/plain" style="height: 300px;"></script>
  </div>
</template>

<script>

const ueditorScripts = [
  'ueditor.config.js?v=3',
  'ueditor.all.js?v=3',
  'lang/zh-cn/zh-cn.js',
  'kityformula-plugin/addKityFormulaDialog.js',
  'kityformula-plugin/getKfContent.js',
  'kityformula-plugin/defaultFilterFix.js'
]
let ueditorLoadPromise = null

function getUeditorBaseUrl () {
  const baseUrl = process.env.BASE_URL || '/'
  return baseUrl.replace(/\/?$/, '/') + 'admin/components/ueditor/'
}

function loadScript (src) {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script')
    script.src = src
    script.onload = resolve
    script.onerror = () => reject(new Error('UEditor script load failed: ' + src))
    document.head.appendChild(script)
  })
}

function loadUeditorScripts () {
  if (!ueditorLoadPromise) {
    const baseUrl = getUeditorBaseUrl()
    window.UEDITOR_HOME_URL = baseUrl
    ueditorLoadPromise = loadScript(baseUrl + ueditorScripts[0]).then(() => {
      window.UEDITOR_HOME_URL = baseUrl
      if (window.UEDITOR_CONFIG) {
        window.UEDITOR_CONFIG.UEDITOR_HOME_URL = baseUrl
      }
      return ueditorScripts.slice(1).reduce((promise, script) => {
        return promise.then(() => loadScript(baseUrl + script))
      }, Promise.resolve())
    }).then(() => {
      if (window.UEDITOR_CONFIG) {
        window.UEDITOR_CONFIG.UEDITOR_HOME_URL = baseUrl
      }
      if (!window.UE) {
        throw new Error('UEditor loaded but window.UE is unavailable')
      }
      return window.UE
    }).catch(error => {
      ueditorLoadPromise = null
      throw error
    })
  }
  return ueditorLoadPromise
}

export default {
  name: 'UE',
  props: {
    value: {
      default: function () {
        return ''
      }
    }
  },
  data () {
    return {
      randomId: 'editor_' + Math.random() * 100000000000000000,
      // 编辑器实例
      instance: null,
      ready: false
    }
  },
  watch: {
    value: function (val) {
      if (val != null && this.ready) {
        this.instance = window.UE.getEditor(this.randomId)
        this.instance.setContent(val)
      }
    }
  },
  mounted () {
    loadUeditorScripts()
      .then(() => {
        this.initEditor()
      })
      .catch(error => {
        this.$message.error('UEditor加载失败')
        throw error
      })
  },

  beforeDestroy () {
    if (this.instance !== null && this.instance.destroy) {
      this.instance.destroy()
    }
  },
  methods: {
    initEditor () {
      this.$nextTick(() => {
        this.instance = window.UE.getEditor(this.randomId)
        this.instance.addListener('ready', () => {
          this.ready = true
          this.$emit('ready', this.instance)
        })
      })
    },
    getUEContent () {
      return this.instance.getContent()
    },
    setText (con) {
      this.instance = window.UE.getEditor(this.randomId)
      this.instance.setContent(con)
    }
  }
}
</script>
