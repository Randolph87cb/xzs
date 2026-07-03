import Vue from 'vue'
import App from './App.vue'
import { router } from './router'
import store from './store'
import 'normalize.css/normalize.css'
import './plugins/element-ui'

import '@/styles/index.scss' // global css
import './icons' // icon
import NProgress from 'nprogress' // progress bar
import 'nprogress/nprogress.css' // progress bar style

Vue.config.productionTip = false

NProgress.configure({ showSpinner: false }) // NProgress Configuration

router.beforeEach(async (to, from, next) => {
  // start progress bar
  NProgress.start()
  if (to.meta.title !== undefined) {
    document.title = to.meta.title
  } else {
    document.title = '\u200E'
  }
  store.commit('router/initRoutes')

  if (to.path && window._hmt) {
    window._hmt.push(['_trackPageview', '/#' + to.fullPath])
  }

  next()
})

router.afterEach(() => {
  // finish progress bar
  NProgress.done()
})

Vue.prototype.$$router = router

new Vue({
  router: router,
  store: store,
  render: h => h(App)
}).$mount('#app')
