<template>
  <div class="app-contain">
    <el-card class="training-card" shadow="never">
      <div slot="header">
        <span>智能训练</span>
      </div>
      <el-form ref="form" :model="form" label-width="90px" v-loading="subjectLoading">
        <el-form-item label="训练科目" prop="subjectId">
          <el-select v-model="form.subjectId" placeholder="请选择科目" class="training-subject-select">
            <el-option v-for="item in subjectList" :key="item.id" :label="item.name" :value="item.id"/>
          </el-select>
        </el-form-item>
        <el-form-item>
          <el-button type="primary" :loading="startLoading" :disabled="subjectList.length === 0" @click="startTraining">开始训练</el-button>
        </el-form-item>
      </el-form>
    </el-card>
  </div>
</template>

<script>
import subjectApi from '@/api/subject'
import examPaperApi from '@/api/examPaper'

export default {
  data () {
    return {
      form: {
        subjectId: null
      },
      subjectList: [],
      subjectLoading: false,
      startLoading: false
    }
  },
  created () {
    this.initSubject()
  },
  methods: {
    initSubject () {
      this.subjectLoading = true
      subjectApi.list().then(re => {
        this.subjectList = re.response || []
        if (this.subjectList.length > 0) {
          this.form.subjectId = this.subjectList[0].id
        }
        this.subjectLoading = false
      }).catch(e => {
        this.subjectLoading = false
      })
    },
    startTraining () {
      if (!this.form.subjectId) {
        this.$message.warning('请选择科目')
        return
      }
      this.startLoading = true
      examPaperApi.smartTrainingCreate({ subjectId: this.form.subjectId }).then(re => {
        if (re.code === 1) {
          const paperId = this.getPaperId(re.response)
          if (paperId) {
            this.$router.push({ path: '/do', query: { id: paperId } })
          } else {
            this.$message.error('训练卷生成失败')
          }
        } else {
          this.$message.error(re.message)
        }
        this.startLoading = false
      }).catch(e => {
        this.startLoading = false
      })
    },
    getPaperId (response) {
      if (response === null || response === undefined) {
        return null
      }
      if (typeof response === 'number' || typeof response === 'string') {
        return response
      }
      return response.id || response.paperId || response.examPaperId
    }
  }
}
</script>

<style lang="scss" scoped>
  .training-card {
    max-width: 520px;
  }

  .training-subject-select {
    width: 100%;
  }
</style>
