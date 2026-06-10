export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[88px] md:pb-6 animate-pulse">
      <div className="h-8 w-24 rounded-xl glass-light" />
      <div className="h-5 w-44 rounded-full glass-light" />
      <div className="h-10 rounded-xl glass-light" />
      <div className="grid grid-cols-2 gap-2">
        <div className="h-10 rounded-xl glass-light" />
        <div className="h-10 rounded-xl glass-light" />
      </div>
      <div className="h-10 rounded-xl glass-light" />
      <div className="h-24 rounded-2xl glass-light" />
      <div className="h-10 w-32 rounded-xl glass-light ml-auto" />
    </div>
  )
}
