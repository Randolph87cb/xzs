<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>个人简介</h1>
        <p>查看并维护当前账号资料。</p>
      </div>
    </header>

    <el-descriptions class="profile-summary" :column="isMobileViewport ? 1 : 2" border>
      <el-descriptions-item label="用户名">{{ userStore.userInfo?.userName }}</el-descriptions-item>
      <el-descriptions-item label="角色">{{ roleLabel }}</el-descriptions-item>
      <el-descriptions-item label="创建时间">{{ userStore.userInfo?.createTime }}</el-descriptions-item>
      <el-descriptions-item label="状态">{{ userStore.userInfo?.status === 1 ? '启用' : '禁用' }}</el-descriptions-item>
    </el-descriptions>

    <el-form class="profile-form" :model="form" label-width="92px">
      <el-form-item label="真实姓名">
        <el-input v-model="form.realName" />
      </el-form-item>
      <el-form-item label="手机">
        <el-input v-model="form.phone" />
      </el-form-item>
      <el-form-item>
        <el-button type="primary" data-testid="profile-save" @click="submit">保存</el-button>
      </el-form-item>
    </el-form>

    <section v-if="canConfigureAiReview" class="profile-section">
      <header>
        <h2>AI 审核配置</h2>
        <p>自动预审会使用错题所属班级负责老师的配置；这里维护当前账号作为班级负责老师时使用的 AI 预审接口。</p>
      </header>
      <div v-if="isMobileViewport" class="profile-section__desktop-hint" role="note">
        <strong>请使用电脑端配置 AI 审核</strong>
        <span>接口地址、模型与 API Key 属于敏感配置，手机端仅支持维护基础个人资料。</span>
      </div>
      <el-form v-else :model="aiForm" label-width="104px" style="max-width: 760px">
        <el-form-item label="启用预审">
          <el-switch v-model="aiForm.enabled" />
        </el-form-item>
        <el-form-item label="接口地址">
          <el-input v-model="aiForm.baseUrl" placeholder="https://api.example.com/v1" />
        </el-form-item>
        <el-form-item label="模型">
          <el-input v-model="aiForm.model" placeholder="gpt-4.1-mini" />
        </el-form-item>
        <el-form-item label="API Key">
          <el-input
            v-model="aiForm.apiKey"
            type="password"
            show-password
            :placeholder="aiForm.hasApiKey ? '已保存，留空则不修改' : '请输入 API Key'"
          />
        </el-form-item>
        <el-form-item v-if="aiForm.hasApiKey" label="清除密钥">
          <el-checkbox v-model="aiForm.clearApiKey">保存时清除已保存的 API Key</el-checkbox>
        </el-form-item>
        <el-form-item label="自定义提示词">
          <el-input v-model="aiForm.prompt" type="textarea" :rows="4" placeholder="留空使用默认预审提示词" />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" :loading="aiSaving" @click="submitAiConfig">保存 AI 配置</el-button>
        </el-form-item>
      </el-form>
    </section>
  </section>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import {
  getAdminQuestionCorrectionAiConfig,
  saveAdminQuestionCorrectionAiConfig,
  updateCurrentAdminUser
} from '@xzs/api-client'
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()
const loading = ref(false)
const aiSaving = ref(false)
const mobileMediaQuery = window.matchMedia('(max-width: 767px)')
const isMobileViewport = ref(mobileMediaQuery.matches)
const aiConfigLoaded = ref(false)
const form = reactive({
  realName: '',
  phone: ''
})
const aiForm = reactive({
  provider: 'openai_compatible',
  baseUrl: '',
  model: '',
  apiKey: '',
  clearApiKey: false,
  enabled: false,
  prompt: '',
  hasApiKey: false
})

const roleLabel = computed(() => {
  if (userStore.userInfo?.role === 2) return '老师'
  if (userStore.userInfo?.role === 3) return '管理员'
  return userStore.userInfo?.role ?? ''
})
const canConfigureAiReview = computed(() => userStore.userInfo?.role === 2 || userStore.userInfo?.role === 3)

onMounted(async () => {
  mobileMediaQuery.addEventListener('change', handleViewportChange)
  await userStore.initUserInfo()
  form.realName = userStore.userInfo?.realName ?? ''
  form.phone = userStore.userInfo?.phone ?? ''
  if (canConfigureAiReview.value && !isMobileViewport.value) {
    await loadAiConfig()
  }
})

onBeforeUnmount(() => {
  mobileMediaQuery.removeEventListener('change', handleViewportChange)
})

function handleViewportChange(event: MediaQueryListEvent) {
  isMobileViewport.value = event.matches
  if (!event.matches && canConfigureAiReview.value && !aiConfigLoaded.value) {
    void loadAiConfig()
  }
}

async function submit() {
  loading.value = true
  try {
    const result = await updateCurrentAdminUser(form)
    ElMessage.success(result.message || '保存成功')
    await userStore.initUserInfo()
  } finally {
    loading.value = false
  }
}

async function loadAiConfig() {
  const result = await getAdminQuestionCorrectionAiConfig()
  const config = result.response
  aiForm.provider = config?.provider ?? 'openai_compatible'
  aiForm.baseUrl = config?.baseUrl ?? ''
  aiForm.model = config?.model ?? ''
  aiForm.apiKey = ''
  aiForm.clearApiKey = false
  aiForm.enabled = config?.enabled ?? false
  aiForm.prompt = config?.prompt ?? ''
  aiForm.hasApiKey = config?.hasApiKey ?? false
  aiConfigLoaded.value = true
}

async function submitAiConfig() {
  aiSaving.value = true
  try {
    const result = await saveAdminQuestionCorrectionAiConfig({
      provider: aiForm.provider,
      baseUrl: aiForm.baseUrl,
      model: aiForm.model,
      apiKey: aiForm.apiKey,
      clearApiKey: aiForm.clearApiKey,
      enabled: aiForm.enabled,
      prompt: aiForm.prompt
    })
    ElMessage.success(result.message || 'AI 配置已保存')
    await loadAiConfig()
  } finally {
    aiSaving.value = false
  }
}
</script>

<style scoped>
.profile-section {
  display: grid;
  gap: 16px;
  margin-top: 28px;
  padding-top: 20px;
  border-top: 1px solid var(--xzs-border);
}

.profile-section h2,
.profile-section p {
  margin: 0;
}

.profile-section h2 {
  color: var(--xzs-text);
  font-size: 18px;
}

.profile-section p {
  margin-top: 4px;
  color: var(--xzs-text-muted);
}

.profile-form {
  max-width: 640px;
}

.profile-section__desktop-hint {
  display: grid;
  gap: 6px;
  padding: 14px;
  border: 1px solid #cfe0ff;
  border-radius: var(--xzs-radius-sm);
  color: #24436f;
  background: #f3f7ff;
}

.profile-section__desktop-hint span {
  color: var(--xzs-text-muted);
  font-size: 13px;
  line-height: 1.6;
}

@media (max-width: 767px) {
  .profile-summary :deep(.el-descriptions__cell) {
    overflow-wrap: anywhere;
  }

  .profile-form {
    width: 100%;
    max-width: none;
  }

  .profile-form .el-button {
    width: 100%;
    min-height: 44px;
    margin-left: 0;
  }

  .profile-section {
    margin-top: 10px;
  }
}
</style>
