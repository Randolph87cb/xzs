import { defineStore } from 'pinia'

interface UserState {
  userName: string
}

export const useUserStore = defineStore('user', {
  state: (): UserState => ({
    userName: ''
  }),
  actions: {
    setUserName(userName: string) {
      this.userName = userName
    },
    clear() {
      this.userName = ''
    }
  }
})
