<template>
  <section class="admin-page" v-loading="loading">
    <header class="admin-page__header">
      <div>
        <h1>智能训练配置</h1>
        <p>配置各学科的训练总题数和知识点上下限规则。</p>
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
      <el-form-item label="知识点规则">
        <div class="smart-rules">
          <el-table :data="form.rules" border>
            <el-table-column label="知识点" min-width="220">
              <template #default="{ row }">
                <el-select v-model="row.knowledgePoint" filterable allow-create default-first-option placeholder="知识点">
                  <el-option v-for="item in knowledgePoints" :key="item" :label="item" :value="item" />
                </el-select>
              </template>
            </el-table-column>
            <el-table-column label="下限" width="140">
              <template #default="{ row }">
                <el-input-number v-model="row.minCount" :min="0" />
              </template>
            </el-table-column>
            <el-table-column label="上限" width="140">
              <template #default="{ row }">
                <el-input-number v-model="row.maxCount" :min="0" />
              </template>
            </el-table-column>
            <el-table-column label="权重" width="140">
              <template #default="{ row }">
                <el-input-number v-model="row.weight" :min="1" />
              </template>
            </el-table-column>
            <el-table-column label="启用" width="100">
              <template #default="{ row }">
                <el-switch v-model="row.enabled" />
              </template>
            </el-table-column>
            <el-table-column label="操作" width="90">
              <template #default="{ $index }">
                <el-button size="small" type="danger" @click="form.rules.splice($index, 1)">删除</el-button>
              </template>
            </el-table-column>
          </el-table>
          <el-button @click="form.rules.push(defaultRule())">添加知识点</el-button>
        </div>
      </el-form-item>
      <el-form-item label="上下限合计">下限 {{ enabledMinCount }} / 上限 {{ enabledMaxCount }} / 总题数 {{ form.questionCount }}</el-form-item>
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
const enabledRules = computed(() => form.rules.filter((item) => item.enabled))
const enabledMinCount = computed(() => enabledRules.value.reduce((total, item) => total + (item.minCount || 0), 0))
const enabledMaxCount = computed(() => enabledRules.value.reduce((total, item) => total + (item.maxCount || 0), 0))

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
    rules: [{ knowledgePoint: '综合', minCount: 20, maxCount: 20, weight: 20, enabled: true }]
  }
}

function defaultRule() {
  return {
    knowledgePoint: '',
    minCount: 0,
    maxCount: 1,
    weight: 1,
    enabled: true
  }
}

function normalizeRule(rule: Partial<AdminSmartTrainingConfig['rules'][number]>): AdminSmartTrainingConfig['rules'][number] {
  const legacyCount = toCount(rule.questionCount, 0)
  const minCount = toCount(rule.minCount ?? rule.questionCount, 0)
  const maxCount = toCount(rule.maxCount ?? rule.questionCount, legacyCount || 1)

  return {
    knowledgePoint: rule.knowledgePoint ?? '',
    minCount,
    maxCount,
    weight: toCount(rule.weight ?? rule.questionCount, legacyCount || 1),
    enabled: rule.enabled ?? true,
    questionCount: rule.questionCount
  }
}

function toCount(value: unknown, fallback: number) {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
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
    form.rules = (form.rules ?? []).map(normalizeRule)
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
  const validationMessage = validateRules()
  if (validationMessage) {
    ElMessage.error(validationMessage)
    return
  }
  const result = await saveAdminSmartTrainingConfig(form)
  ElMessage.success(result.message || '保存成功')
  await loadConfigList()
}

function subjectName(subjectId?: number | null) {
  return subjects.value.find((item) => item.id === subjectId)?.name ?? ''
}

function validateRules() {
  const knowledgePointSet = new Set<string>()

  for (const item of form.rules) {
    const knowledgePoint = item.knowledgePoint.trim()
    if (!knowledgePoint) {
      return '知识点不能为空'
    }
    if (knowledgePointSet.has(knowledgePoint)) {
      return '知识点不能重复'
    }
    knowledgePointSet.add(knowledgePoint)

    if (item.minCount > item.maxCount) {
      return '每条知识点规则的下限不能大于上限'
    }
  }

  if (enabledMinCount.value > form.questionCount) {
    return '启用规则的下限合计不能大于总题数'
  }

  if (enabledMaxCount.value < form.questionCount) {
    return '启用规则的上限合计不能小于总题数'
  }

  return ''
}
</script>

<style scoped>
.smart-rules {
  display: grid;
  gap: 10px;
  width: 100%;
}
</style>
