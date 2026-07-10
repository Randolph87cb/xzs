<template>
  <el-container class="shell">
    <el-header class="shell__header">
      <div class="shell__brand">
        <img class="shell__mark" :src="appIconUrl" alt="" />
        <div>
          <strong>信息学客观题一本通</strong>
          <span>GESP/CSP 客观题训练</span>
        </div>
      </div>
      <el-menu mode="horizontal" router :default-active="$route.path" class="shell__menu">
        <el-menu-item index="/index">首页</el-menu-item>
        <el-menu-item index="/paper/index">试卷中心</el-menu-item>
        <el-menu-item index="/training/index">智能训练</el-menu-item>
        <el-menu-item index="/record/index">考试记录</el-menu-item>
        <el-menu-item index="/question/index">错题本</el-menu-item>
        <el-menu-item index="/ranking/class">班级排行</el-menu-item>
        <el-menu-item index="/user/index">个人中心</el-menu-item>
      </el-menu>
      <div class="shell__tools">
        <span class="shell__user-name">{{ userStore.displayName }}</span>
        <el-button :icon="Search" circle text aria-label="搜索" />
        <el-button text @click="handleLogout">退出</el-button>
      </div>
    </el-header>
    <el-main class="shell__main">
      <RouterView />
    </el-main>
  </el-container>
</template>

<script setup lang="ts">
import { Search } from '@element-plus/icons-vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'

const router = useRouter()
const userStore = useUserStore()
const appIconUrl = `${import.meta.env.BASE_URL}app-icon.svg`

async function handleLogout() {
  await userStore.logout()
  router.push('/login')
}
</script>

<style scoped lang="scss">
.shell {
  min-height: 100vh;
  background: var(--xzs-bg);
}

.shell__header {
  display: flex;
  align-items: center;
  gap: 22px;
  height: 64px;
  padding: 0 24px;
  border-bottom: 1px solid var(--xzs-border);
  background: rgb(255 255 255 / 94%);
  backdrop-filter: blur(10px);
}

.shell__brand {
  display: flex;
  align-items: center;
  gap: 12px;
  flex: 0 0 auto;
  min-width: 212px;
  color: var(--xzs-text);
}

.shell__mark {
  width: 34px;
  height: 34px;
  border-radius: 8px;
  display: block;
  box-shadow: 0 10px 20px rgb(23 105 255 / 24%);
}

.shell__brand div {
  display: grid;
  gap: 2px;
}

.shell__brand strong {
  font-size: 16px;
  line-height: 1;
}

.shell__brand span:last-child {
  color: var(--xzs-text-soft);
  font-size: 12px;
}

.shell__menu {
  flex: 1 1 auto;
  border-bottom: 0;
}

.shell__tools {
  display: flex;
  align-items: center;
  gap: 8px;
}

.shell__user-name {
  max-width: 140px;
  overflow: hidden;
  color: var(--xzs-text);
  font-size: 14px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.shell__main {
  width: min(1180px, calc(100vw - 32px));
  margin: 0 auto;
  padding: 24px 0;
}

@media (max-width: 920px) {
  .shell__header {
    align-items: stretch;
    flex-direction: column;
    height: auto;
    padding: 12px 16px;
  }

  .shell__menu {
    width: 100%;
    overflow-x: auto;
  }

  .shell__tools {
    display: none;
  }
}
</style>
