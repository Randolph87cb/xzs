<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>智能训练配置</h1>
        <p>配置各学科的训练题数和知识点配比。</p>
      </div>
    </header>

    <section class="admin-page__filters">
      <el-select v-model="selectedSubjectId" placeholder="请选择学科" @change="handleSubjectChange">
        <el-option v-for="item in subjects" :key="item.id" :label="item.name" :value="item.id" />
      </el-select>
      <el-button :disabled="!selectedSubjectId" @click="loadSubjectConfig">加载配置</el-button>
    </section>

    <el-form :model="form" label-width="110px">
      <el-form-item label="总题数">
        <el-input-number v-model="form.questionCount" :min="1" />
      </el-form-item>
      <el-form-item label="知识点配比">
        <div class="smart-rules">
          <el-table :data="form.rules" border>
            <el-table-column label="知识点" min-width="220">
              <template #default="{ row }">
                <el-select v-model="row.knowledgePoint" filterable allow-create default-first-option placeholder="知识点">
                  <el-option v-for="item in knowledgePoints" :key="item" :label="item" :value="item" />
                </el-select>
              </template>
            </el-table-column>
            <el-table-column label="题数" width="160">
              <template #default="{ row }">
                <el-input-number v-model="row.questionCount" :min="1" />
              </template>
            </el-table-column>
            <el-table-column label="操作" width="90">
              <template #default="{ $index }">
                <el-button size="small" type="danger" @click="form.rules.splice($index, 1)">删除</el-button>
              </template>
            </el-table-column>
          </el-table>
          <el-button @click="form.rules.push({ knowledgePoint: '', questionCount: 1 })">添加知识点</el-button>
        </div>
      </el-form-item>
      <el-form-item label="配比合计">{{ ruleQuestionCount }}</el-form-item>
      <el-form-item>
        <el-button type="primary" data-testid="smart-training-save" :disabled="!form.subjectId" @click="submit">保存</el-button>
      </el-form-item>
    </el-form>

    <el-table :data="configs" border>
      <el-table-column prop="id" label="Id" width="90" />
      <el-table-column label="学科" min-width="160">
        <template #default="{ row }">{{ subjectName(row.subjectId) }}</template>
      </el-table-column>
      <el-table-column prop="questionCount" label="总题数" width="120" />
      <el-table-column label="操作" width="100">
        <template #default="{ row }">
          <el-button size="small" @click="selectConfig(row.subjectId)">编辑</el-button>
        </template>
      </el-table-column>
    </el-table>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import {
  getAdminSmartTrainingConfig,
  getAdminSmartTrainingConfigList,
  getAdminSmartTrainingKnowledgePoints,
  getAdminSubjectPage,
  saveAdminSmartTrainingConfig,
  type AdminSmartTrainingConfig,
  type AdminSubjectListItem
} from '@xzs/api-client'

const loading = ref(false)
const subjects = ref<AdminSubjectListItem[]>([])
const configs = ref<AdminSmartTrainingConfig[]>([])
const knowledgePoints = ref<string[]>([])
const selectedSubjectId = ref<number | null>(null)
const form = reactive<AdminSmartTrainingConfig>(defaultForm())
const ruleQuestionCount = computed(() => form.rules.reduce((total, item) => total + (item.questionCount || 0), 0))

onMounted(async () => {
  const subjectResult = await getAdminSubjectPage({ pageIndex: 1, pageSize: 100 })
  subjects.value = subjectResult.response?.list ?? []
  await loadConfigList()
})

function defaultForm(): AdminSmartTrainingConfig {
  return {
    id: null,
    subjectId: null,
    questionCount: 20,
    rules: [{ knowledgePoint: '综合', questionCount: 20 }]
  }
}

async function loadConfigList() {
  const result = await getAdminSmartTrainingConfigList()
  configs.value = result.response ?? []
}

async function handleSubjectChange() {
  await loadKnowledgePoints()
  await loadSubjectConfig()
}

async function loadKnowledgePoints() {
  knowledgePoints.value = []
  if (!selectedSubjectId.value) return
  const result = await getAdminSmartTrainingKnowledgePoints(selectedSubjectId.value)
  knowledgePoints.value = result.response ?? []
}

async function loadSubjectConfig() {
  if (!selectedSubjectId.value) {
    Object.assign(form, defaultForm())
    return
  }
  loading.value = true
  try {
    const result = await getAdminSmartTrainingConfig(selectedSubjectId.value)
    Object.assign(form, defaultForm(), result.response, { subjectId: selectedSubjectId.value })
    if (!form.rules?.length) {
      form.rules = []
    }
  } finally {
    loading.value = false
  }
}

async function selectConfig(subjectId: number | null) {
  selectedSubjectId.value = subjectId
  await handleSubjectChange()
}

async function submit() {
  if (!form.subjectId) {
    ElMessage.error('请选择学科')
    return
  }
  if (ruleQuestionCount.value !== form.questionCount) {
    ElMessage.error('知识点配比题数合计需等于总题数')
    return
  }
  const result = await saveAdminSmartTrainingConfig(form)
  ElMessage.success(result.message || '保存成功')
  await loadConfigList()
}

function subjectName(subjectId?: number | null) {
  return subjects.value.find((item) => item.id === subjectId)?.name ?? ''
}
</script>

<style scoped>
.smart-rules {
  display: grid;
  gap: 10px;
  width: 100%;
}
</style>
