<template>
  <main v-if="isInitialNavigationPending" class="startup" aria-live="polite" aria-busy="true">
    <section class="startup__content">
      <span class="startup__indicator" aria-hidden="true"></span>
      <div>
        <h1>信息学客观题一本通</h1>
        <p>正在准备学习空间…</p>
      </div>
    </section>
  </main>
  <RouterView v-else />
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'

const router = useRouter()
const isInitialNavigationPending = ref(true)
const finishInitialNavigation = () => {
  isInitialNavigationPending.value = false
}

router.isReady().then(finishInitialNavigation, finishInitialNavigation)
</script>

<style scoped lang="scss">
.startup {
  display: grid;
  min-height: 100vh;
  place-items: center;
  padding: 24px;
  background:
    linear-gradient(135deg, rgb(23 105 255 / 8%), transparent 42%),
    var(--xzs-bg);
}

.startup__content {
  display: flex;
  align-items: center;
  gap: 14px;
  color: var(--xzs-text);
}

.startup__content h1,
.startup__content p {
  margin: 0;
}

.startup__content h1 {
  font-size: 20px;
}

.startup__content p {
  margin-top: 5px;
  color: var(--xzs-text-muted);
  font-size: 13px;
}

.startup__indicator {
  width: 28px;
  height: 28px;
  border: 3px solid rgb(23 105 255 / 18%);
  border-top-color: var(--xzs-primary);
  border-radius: 50%;
  animation: startup-spin 0.8s linear infinite;
}

@keyframes startup-spin {
  to {
    transform: rotate(360deg);
  }
}

@media (prefers-reduced-motion: reduce) {
  .startup__indicator {
    animation: none;
    border-top-color: rgb(23 105 255 / 18%);
    background: var(--xzs-primary);
    box-shadow: inset 0 0 0 8px var(--xzs-bg);
  }
}
</style>
