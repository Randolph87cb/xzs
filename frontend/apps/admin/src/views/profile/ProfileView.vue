<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>个人简介</h1>
        <p>查看并维护当前账号资料。</p>
      </div>
    </header>

    <el-descriptions :column="2" border>
      <el-descriptions-item label="用户名">{{ userStore.userInfo?.userName }}</el-descriptions-item>
      <el-descriptions-item label="角色">{{ roleLabel }}</el-descriptions-item>
      <el-descriptions-item label="创建时间">{{ userStore.userInfo?.createTime }}</el-descriptions-item>
      <el-descriptions-item label="状态">{{ userStore.userInfo?.status === 1 ? '启用' : '禁用' }}</el-descriptions-item>
    </el-descriptions>

    <el-form :model="form" label-width="92px" style="max-width: 640px">
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
      <el-form :model="aiForm" label-width="104px" style="max-width: 760px">
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
import { computed, onMounted, reactive, ref } from 'vue'
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
  await userStore.initUserInfo()
  form.realName = userStore.userInfo?.realName ?? ''
  form.phone = userStore.userInfo?.phone ?? ''
  if (canConfigureAiReview.value) {
    await loadAiConfig()
  }
})

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
</style>
