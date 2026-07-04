<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>个人简介</h1>
        <p>查看并维护当前管理员资料。</p>
      </div>
    </header>

    <el-descriptions :column="2" border>
      <el-descriptions-item label="用户名">{{ userStore.userInfo?.userName }}</el-descriptions-item>
      <el-descriptions-item label="角色">{{ userStore.userInfo?.role === 3 ? '管理员' : userStore.userInfo?.role }}</el-descriptions-item>
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
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { updateCurrentAdminUser } from '@xzs/api-client'
import { useUserStore } from '@/stores/user'

const userStore = useUserStore()
const loading = ref(false)
const form = reactive({
  realName: '',
  phone: ''
})

onMounted(async () => {
  await userStore.initUserInfo()
  form.realName = userStore.userInfo?.realName ?? ''
  form.phone = userStore.userInfo?.phone ?? ''
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
</script>
