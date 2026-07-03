<template>
  <div style="line-height:1.8">
    <div v-if="qType==1" v-loading="qLoading">
      <MarkdownView class="q-title" :content="question.title"/>
      <div class="q-content">
          <span :key="item.id" v-for="item in question.items" class="q-item-contain">
            <span class="q-item-prefix">{{item.prefix}}</span>
            <MarkdownView class="q-item-content" :content="item.content"/>
          </span>
      </div>
    </div>
    <div v-else-if="qType==2" v-loading="qLoading">
      <MarkdownView class="q-title" :content="question.title"/>
      <div class="q-content">
          <span :key="item.id" v-for="item in question.items" class="q-item-contain">
            <span class="q-item-prefix">{{item.prefix}}</span>
            <MarkdownView class="q-item-content" :content="item.content"/>
          </span>
      </div>
    </div>
    <div v-else-if="qType==3" v-loading="qLoading">
      <MarkdownView class="q-title" :content="question.title"/>
      <span>（</span>
      <span :key="item.id" v-for="item in question.items">
        <MarkdownView class="q-item-content" :content="item.content"/>
       </span>
      <span>）</span>
    </div>
    <div v-else-if="qType==4" v-loading="qLoading">
      <MarkdownView class="q-title" :content="question.title"/>
    </div>
    <div v-else-if="qType==5" v-loading="qLoading">
      <MarkdownView class="q-title" :content="question.title"/>
    </div>
    <div v-else>
    </div>
  </div>

</template>

<script>
import MarkdownView from '@/components/MarkdownView'

export default {
  name: 'QuestionShow',
  components: { MarkdownView },
  props: {
    question: {
      type: Object,
      default: function () {
        return {}
      }
    },
    qLoading: {
      type: Boolean,
      default: false
    },
    qType: {
      type: Number,
      default: 0
    }
  },
  methods: {}
}
</script>
