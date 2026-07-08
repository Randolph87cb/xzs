<template>
  <main class="not-found">
    <section class="not-found__panel">
      <p class="not-found__code">404</p>
      <h1>页面不存在</h1>
      <el-button type="primary" @click="router.replace('/index')">返回首页</el-button>
    </section>
  </main>
</template>

<script setup lang="ts">
import { useRouter } from 'vue-router'

const router = useRouter()
</script>

<style scoped lang="scss">
.not-found {
  display: grid;
  min-height: 100vh;
  place-items: center;
  padding: 24px;
  background: var(--xzs-bg);
}

.not-found__panel {
  width: min(360px, 100%);
  padding: 28px;
  border: 1px solid var(--xzs-border);
  border-radius: 6px;
  background: var(--xzs-surface);
  text-align: center;
}

.not-found__code {
  margin: 0 0 8px;
  color: var(--xzs-primary);
  font-size: 40px;
  font-weight: 700;
}

.not-found__panel h1 {
  margin: 0 0 20px;
  color: var(--xzs-text);
  font-size: 22px;
}
</style>
