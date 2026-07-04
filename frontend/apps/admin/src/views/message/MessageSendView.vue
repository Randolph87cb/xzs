<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>消息发送</h1>
        <p>向指定用户发送站内消息。</p>
      </div>
    </header>

    <el-form ref="formRef" :model="form" :rules="rules" label-width="92px">
      <el-form-item label="标题" prop="title">
        <el-input v-model="form.title" />
      </el-form-item>
      <el-form-item label="内容" prop="content">
        <el-input v-model="form.content" type="textarea" :rows="10" />
      </el-form-item>
      <el-form-item label="接收人" prop="receiveUserIds">
        <el-select
          v-model="form.receiveUserIds"
          multiple
          filterable
          remote
          reserve-keyword
          placeholder="输入用户名搜索"
          :remote-method="searchUsers"
          :loading="selectLoading"
          style="width: 100%"
        >
          <el-option v-for="item in userOptions" :key="item.value" :label="item.name" :value="item.value" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" data-testid="message-send-submit" @click="submit">发送</el-button>
        <el-button @click="reset">重置</el-button>
      </el-form-item>
    </el-form>
  </section>
</template>

<script setup lang="ts">
import { reactive, ref } from 'vue'
import { ElMessage, type FormInstance, type FormRules } from 'element-plus'
import { useRouter } from 'vue-router'
import { selectAdminUsersByName, sendAdminMessage, type AdminUserOption } from '@xzs/api-client'

const router = useRouter()
const formRef = ref<FormInstance>()
const loading = ref(false)
const selectLoading = ref(false)
const userOptions = ref<AdminUserOption[]>([])
const form = reactive({
  title: '',
  content: '',
  receiveUserIds: [] as number[]
})
const rules: FormRules = {
  title: [{ required: true, message: '请输入消息标题', trigger: 'blur' }],
  content: [{ required: true, message: '请输入消息内容', trigger: 'blur' }],
  receiveUserIds: [{ required: true, type: 'array', min: 1, message: '请选择接收人', trigger: 'change' }]
}

async function searchUsers(query: string) {
  if (!query) {
    userOptions.value = []
    return
  }

  selectLoading.value = true
  try {
    const result = await selectAdminUsersByName(query)
    userOptions.value = result.response ?? []
  } finally {
    selectLoading.value = false
  }
}

async function submit() {
  const valid = await formRef.value?.validate()
  if (!valid) {
    return
  }

  loading.value = true
  try {
    const result = await sendAdminMessage(form)
    ElMessage.success(result.message || '发送成功')
    router.push('/message/list')
  } finally {
    loading.value = false
  }
}

function reset() {
  form.title = ''
  form.content = ''
  form.receiveUserIds = []
  formRef.value?.clearValidate()
}
</script>
