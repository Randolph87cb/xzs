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
  background: #f5f7fb;
}

.not-found__panel {
  width: min(360px, 100%);
  padding: 28px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
  text-align: center;
}

.not-found__code {
  margin: 0 0 8px;
  color: #2563eb;
  font-size: 40px;
  font-weight: 700;
}

.not-found__panel h1 {
  margin: 0 0 20px;
  color: #111827;
  font-size: 22px;
}
</style>
